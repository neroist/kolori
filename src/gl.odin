package kolori

import opengl "vendor:OpenGL"
import sdl "vendor:sdl3"
import "base:runtime"
import "core:log"
import "core:fmt"

GL_State :: struct {
	abcd:             [4]Color,
	uniforms:         Uniforms,
	shift:            [2]f32,
	// resolution:       [2]f32,
	ctx:              sdl.GLContext,
	vao:              u32,
	program:          u32,
	vertex_shader_id: u32,
	texture:          u32,
	zoom:             f32,
	time:             f32,
	gamma_correction: f32,
	saturation:       f32,
	lightness:        f32,
	texture_wrap_s:   i32,
	texture_wrap_t:   i32,
	texture_min_fltr: i32,
	texture_mag_fltr: i32,
}

Color :: [3]f32

// use uniform buffer object and a single "set_uniforms" proc (UBO)?
// Uniform :: struct($T: typeid) {
// 	location: i32,
// 	value: T
// }
// Uniforms :: struct {
// 	zoom:             Uniform(f32),
// 	time:             Uniform(f32),
// 	resolution:       Uniform([2]f32),
// 	shift:            Uniform([2]f32),
// 	abcd:             Uniform([4]Color),
// 	gamma_correction: Uniform(f32),
// 	saturation:       Uniform(f32),
// 	lightness:        Uniform(f32),
// }

Uniforms :: struct {
	zoom:             i32,
	time:             i32,
	resolution:       i32,
	shift:            i32,
	abcd:             i32,
	gamma_correction: i32,
	saturation:       i32,
	lightness:        i32,
}

when ODIN_DEBUG {
	// for glDebugMessageCallback
	GL_MAJOR_VERSION :: 4
	GL_MINOR_VERSION :: 3
} else {
	GL_MAJOR_VERSION :: 3
	GL_MINOR_VERSION :: 3
}

@(rodata)
VERTEX_SHADER := #load("shaders/graph.vert", string)

@(rodata)
FRAGMENT_SHADER := #load("shaders/graph.frag", cstring)

setup_gl :: proc(app: ^App_State) 
{
	app.gl.ctx = sdl.GL_CreateContext(app.window)
	if app.gl.ctx == nil {
		log.fatal(
			"[sdl.GL_CreateContext] Failed to create an OpenGL context. Error msg:",
			sdl.GetError(),
		)

		app.running = false
		return
	}

	context_flags: sdl.GLContextFlag
	when ODIN_DEBUG {
		context_flags |= sdl.GL_CONTEXT_DEBUG_FLAG
	}
	when ODIN_OS == .Darwin {
		context_flags |= sdl.GL_CONTEXT_FORWARD_COMPATIBLE_FLAG
	}

	// See odin-lang/Odin issue 2123: https://github.com/odin-lang/odin/issues/2123
	sdl.GL_SetAttribute(.CONTEXT_FLAGS, transmute(i32)(context_flags))
	sdl.GL_SetAttribute(
		.CONTEXT_PROFILE_MASK,
		(i32)(sdl.GL_CONTEXT_PROFILE_CORE),
	)
	sdl.GL_SetAttribute(.CONTEXT_MAJOR_VERSION, GL_MAJOR_VERSION)
	sdl.GL_SetAttribute(.CONTEXT_MINOR_VERSION, GL_MINOR_VERSION)
	sdl.GL_SetAttribute(.DOUBLEBUFFER, 1)
	sdl.GL_SetAttribute(.DEPTH_SIZE, 24)
	sdl.GL_SetAttribute(.STENCIL_SIZE, 8)

	app.vsync = sdl.GL_SetSwapInterval(1)

	sdl.GL_MakeCurrent(app.window, app.gl.ctx)

	opengl.load_up_to(
		GL_MAJOR_VERSION,
		GL_MINOR_VERSION,
		sdl.gl_set_proc_address,
	)

	when ODIN_DEBUG {
		opengl.DebugMessageCallback(debug_proc, nil)
		opengl.Enable(opengl.DEBUG_OUTPUT)
		opengl.Enable(opengl.DEBUG_OUTPUT_SYNCHRONOUS)
	}

	width, height: i32
	sdl.GetWindowSizeInPixels(app.window, &width, &height)
	opengl.Viewport(0, 0, width, height)

	vertices := [?]f32 {
		// Coordinates 
		-1,
		1,
		1,
		1,
		-1,
		-1,
		1,
		-1,
	}

	opengl.GenVertexArrays(1, &app.vao)
	opengl.BindVertexArray(app.vao)

	opengl.GenTextures(1, &app.texture)
	opengl.BindTexture(opengl.TEXTURE_2D, app.texture)
	app.texture_wrap_s = opengl.REPEAT // these are the default
	app.texture_wrap_t = opengl.REPEAT
	app.texture_min_fltr = opengl.LINEAR_MIPMAP_LINEAR
	app.texture_mag_fltr = opengl.LINEAR

	vbo: u32
	opengl.GenBuffers(1, &vbo)
	opengl.BindBuffer(opengl.ARRAY_BUFFER, vbo)

	opengl.BufferData(
		opengl.ARRAY_BUFFER, // target
		size_of(vertices), // size of the buffer object's data store
		&vertices, // data used for initialization
		opengl.STATIC_DRAW, // usage
	)

	opengl.VertexAttribPointer(
		0, // index
		2, // size
		opengl.FLOAT, // type
		opengl.FALSE, // normalized
		2 * size_of(f32), // stride
		0, // offset
	)

	opengl.EnableVertexAttribArray(0)

	ok: bool
	app.vertex_shader_id, ok = opengl.compile_shader_from_source(
		VERTEX_SHADER,
		.VERTEX_SHADER,
	)
	if !ok {
		log.fatal("Could not compile vertex shader")
	}

	reload_shaders(app)
	opengl.Uniform1i(opengl.GetUniformLocation(app.program, "tex"), 0)
}

render_graph :: proc(app: ^App_State) 
{
	opengl.UseProgram(app.program)
	opengl.BindVertexArray(app.vao)

	// Draw commands.
	opengl.ClearColor(0.1, 0.1, 0.1, 1)
	opengl.Clear(opengl.COLOR_BUFFER_BIT)

	opengl.DrawArrays(
		opengl.TRIANGLE_STRIP, // Draw triangles.
		0, // Begin drawing at index 0.
		4, // Use 4 indices.
	)
}

reload_shaders :: proc(app: ^App_State) 
{
	compile_fragment_shader :: proc(sources: []cstring) -> (id: u32, ok: bool) 
	{
		lengths := make([dynamic]i32, 0, len(sources), context.temp_allocator)
		for i in sources {
			append(&lengths, (i32)(len(i)))
		}

		id = opengl.CreateShader(opengl.FRAGMENT_SHADER)
		opengl.ShaderSource(
			id,
			(i32)(len(sources)),
			raw_data(sources),
			raw_data(lengths),
		)
		opengl.CompileShader(id)

		success: i32
		opengl.GetShaderiv(id, opengl.COMPILE_STATUS, &success)
		if success == 0 {
			return id, false
		}

		return id, true
	}

	opengl.UseProgram(0)
	opengl.DeleteProgram(app.program)

	@(static, rodata)
	coloring_method_headers := [Coloring_Method]cstring {
		.Use_HSL     = "#define USE_HSL\n",
		.Use_HSLuv   = "#define USE_HSLUV\n",
		.Use_Palette = "#define USE_PALETTE\n",
		.Use_Image   = "#define USE_IMAGE\n",
	}

	// we all <3 pointer arithmetic!
	frag_ptr := transmute(uintptr)(FRAGMENT_SHADER)
	frag_wanted_part := transmute(cstring)(frag_ptr + 16)

	fragment_shader_id, ok := compile_fragment_shader(
		{
			"#version 300 es\n",
			coloring_method_headers[app.coloring_method],
			frag_wanted_part,
			translate(app.function),
		},
	)
	defer opengl.DeleteShader(fragment_shader_id)

	if !ok {
		info_log: [512]u8
		opengl.GetShaderInfoLog(
			fragment_shader_id,
			len(info_log),
			nil,
			([^]u8)(&info_log),
		)
		msg := fmt.ctprintf(
			"[compile_fragment_shader] Failed to compile fragment shader. Error msg:\n\n\"%s\".",
			info_log,
		)

		log.fatal(msg)
		sdl.ShowSimpleMessageBox({.ERROR}, "Failure!", msg, app.window)
		app.running = false

		return
	}

	app.program, ok = opengl.create_and_link_program(
		{app.vertex_shader_id, fragment_shader_id},
	)

	if !ok {
		gl_err_msg, _ := opengl.get_last_error_message()
		msg := fmt.ctprintf(
			"[opengl.create_and_link_program] Failed to compile shader program. Error msg:\n\n\"%s\".",
			gl_err_msg,
		)

		log.fatal(msg)
		sdl.ShowSimpleMessageBox({.ERROR}, "Failure!", msg, app.window)
		app.running = false

		return
	}

	opengl.UseProgram(app.program)

	app.uniforms = {
		zoom             = opengl.GetUniformLocation(app.program, "zoom"),
		time             = opengl.GetUniformLocation(app.program, "time"),
		resolution       = opengl.GetUniformLocation(app.program, "resolution"),
		shift            = opengl.GetUniformLocation(app.program, "shift"),
		abcd             = opengl.GetUniformLocation(app.program, "abcd"),
		saturation       = opengl.GetUniformLocation(app.program, "saturation"),
		lightness        = opengl.GetUniformLocation(app.program, "lightness"),
		gamma_correction = opengl.GetUniformLocation(
			app.program,
			"gamma_correction",
		),
	}

	width, height: i32
	sdl.GetWindowSizeInPixels(app.window, &width, &height)
	opengl.Viewport(0, 0, width, height)
	opengl.Uniform2f(app.uniforms.resolution, (f32)(width), (f32)(height))
	opengl.Uniform2f(app.uniforms.shift, app.shift.x, app.shift.y)
	opengl.Uniform1f(app.uniforms.zoom, app.zoom)
	opengl.Uniform1f(app.uniforms.time, app.time)
	opengl.Uniform1f(app.uniforms.gamma_correction, app.gamma_correction)
	opengl.Uniform3fv(app.uniforms.abcd, 4, ([^]f32)(&app.abcd))
	opengl.Uniform1f(app.uniforms.saturation, app.saturation)
	opengl.Uniform1f(app.uniforms.lightness, app.lightness)
}

load_texture :: proc(app: ^App_State, w, h: i32, pixels: [^]u8) 
{
	opengl.DeleteTextures(1, &app.texture)
	opengl.GenTextures(1, &app.texture)
	opengl.BindTexture(opengl.TEXTURE_2D, app.texture)

	// https://stackoverflow.com/a/49126350
	opengl.PixelStorei(opengl.UNPACK_ALIGNMENT, 1)
	opengl.PixelStorei(opengl.UNPACK_ROW_LENGTH, 0)
	opengl.TexImage2D(
		opengl.TEXTURE_2D,
		0,
		opengl.RGB,
		w,
		h,
		0,
		opengl.RGB,
		opengl.UNSIGNED_BYTE,
		pixels,
	)
	set_tex_parameters(app.texture_wrap_s, app.texture_wrap_t)
	opengl.GenerateMipmap(opengl.TEXTURE_2D)

}

set_tex_parameters :: proc(wrap_s, wrap_t: i32) 
{
	opengl.TexParameteri(opengl.TEXTURE_2D, opengl.TEXTURE_WRAP_S, wrap_s)
	opengl.TexParameteri(opengl.TEXTURE_2D, opengl.TEXTURE_WRAP_T, wrap_t)
	opengl.TexParameteri(
		opengl.TEXTURE_2D,
		opengl.TEXTURE_MIN_FILTER,
		opengl.LINEAR_MIPMAP_LINEAR,
	)
	opengl.TexParameteri(
		opengl.TEXTURE_2D,
		opengl.TEXTURE_MAG_FILTER,
		opengl.LINEAR,
	)
}

debug_proc :: proc "c" (
	source: u32,
	type: u32,
	id: u32,
	severity: u32,
	length: i32,
	message: cstring,
	user_param: rawptr,
) 
{
	Message_Source :: enum u32 {
		API             = opengl.DEBUG_SOURCE_API,
		Window_System   = opengl.DEBUG_SOURCE_WINDOW_SYSTEM,
		Shader_Compiler = opengl.DEBUG_SOURCE_SHADER_COMPILER,
		Third_Party     = opengl.DEBUG_SOURCE_THIRD_PARTY,
		Application     = opengl.DEBUG_SOURCE_APPLICATION,
		Other           = opengl.DEBUG_SOURCE_OTHER,
	}

	Message_Type :: enum u32 {
		Error               = opengl.DEBUG_TYPE_ERROR,
		Deprecated_Behavior = opengl.DEBUG_TYPE_DEPRECATED_BEHAVIOR,
		Undefined_Behavior  = opengl.DEBUG_TYPE_UNDEFINED_BEHAVIOR,
		Portability         = opengl.DEBUG_TYPE_PORTABILITY,
		Performance         = opengl.DEBUG_TYPE_PERFORMANCE,
		Other               = opengl.DEBUG_TYPE_OTHER,
	}

	context = runtime.default_context()
	context.logger = log.create_console_logger()
	context.logger.options = {.Level, .Time}
	defer log.destroy_console_logger(context.logger)

	src := (Message_Source)(source)
	typ := (Message_Type)(type)
	format :: "[OpenGL] [source: %s; type: %s] %s"

	switch severity {
	case opengl.DEBUG_SEVERITY_HIGH:
		log.errorf(format, src, typ, message)
	case opengl.DEBUG_SEVERITY_MEDIUM:
		log.warnf(format, src, typ, message)
	case opengl.DEBUG_SEVERITY_LOW:
		log.infof(format, src, typ, message)
	// on linux the notification messages are annoying and unhelpful
	// case opengl.DEBUG_SEVERITY_NOTIFICATION:
	// 	log.debugf(format, src, typ, message)
	}
}
