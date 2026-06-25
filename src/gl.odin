package kolori

import opengl "vendor:OpenGL"
import sdl "vendor:sdl3"
import "base:runtime"
import "core:log"
import "core:fmt"

GL_State :: struct {
	using uniforms:   Uniforms,
	texture:          Texture,
	ctx:              sdl.GLContext,
	vao:              u32,
	program:          u32,
	vertex_shader_id: u32,
}

Uniforms :: struct {
	abcd:             Uniform([4]Color),
	resolution:       Uniform([2]f32),
	shift:            Uniform([2]f32),
	zoom:             Uniform(f32),
	time:             Uniform(f32),
	gamma_correction: Uniform(f32),
	saturation:       Uniform(f32),
	lightness:        Uniform(f32),
}

Texture :: struct {
	id:         u32,
	wrap_s:     i32,
	wrap_t:     i32,
	min_filter: i32,
	mag_filter: i32,
}

Uniform :: struct($T: typeid) {
	loc: i32,
	val: T
}

Color :: [3]f32

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
		log.fatalf(
			"[sdl.GL_CreateContext] Failed to create an OpenGL context. Error msg: \"%s\"",
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
	sdl.GL_SetAttribute(.CONTEXT_PROFILE_MASK, (i32)(sdl.GL_CONTEXT_PROFILE_CORE))
	sdl.GL_SetAttribute(.CONTEXT_MAJOR_VERSION, GL_MAJOR_VERSION)
	sdl.GL_SetAttribute(.CONTEXT_MINOR_VERSION, GL_MINOR_VERSION)
	sdl.GL_SetAttribute(.DOUBLEBUFFER, 1)
	sdl.GL_SetAttribute(.DEPTH_SIZE, 24)
	sdl.GL_SetAttribute(.STENCIL_SIZE, 8)

	app.vsync = sdl.GL_SetSwapInterval(1)

	sdl.GL_MakeCurrent(app.window, app.gl.ctx)

	opengl.load_up_to(GL_MAJOR_VERSION, GL_MINOR_VERSION, sdl.gl_set_proc_address)

	when ODIN_DEBUG {
		opengl.DebugMessageCallback(debug_proc, nil)
		opengl.Enable(opengl.DEBUG_OUTPUT)
		opengl.Enable(opengl.DEBUG_OUTPUT_SYNCHRONOUS)
	}

	width, height: i32
	sdl.GetWindowSizeInPixels(app.window, &width, &height)
	opengl.Viewport(0, 0, width, height)

	vertices := [?]f32 {
		-1,  1,
		 1,  1,
		-1, -1,
		 1, -1,
	}

	opengl.GenVertexArrays(1, &app.vao)
	opengl.BindVertexArray(app.vao)

	opengl.GenTextures(1, &app.texture.id)
	opengl.BindTexture(opengl.TEXTURE_2D, app.texture.id)
	defer opengl.Uniform1i(opengl.GetUniformLocation(app.program, "tex"), 0)
	app.texture.wrap_s = opengl.REPEAT
	app.texture.wrap_t = opengl.REPEAT
	app.texture.min_filter = opengl.LINEAR_MIPMAP_LINEAR
	app.texture.mag_filter = opengl.LINEAR

	vbo: u32
	opengl.GenBuffers(1, &vbo)
	opengl.BindBuffer(opengl.ARRAY_BUFFER, vbo)
	opengl.BufferData(opengl.ARRAY_BUFFER, size_of(vertices), &vertices, opengl.STATIC_DRAW)
	opengl.VertexAttribPointer(0, 2, opengl.FLOAT, opengl.FALSE, 2 * size_of(f32), 0)
	opengl.EnableVertexAttribArray(0)

	ok: bool
	app.vertex_shader_id, ok = opengl.compile_shader_from_source(VERTEX_SHADER, .VERTEX_SHADER)
	if !ok {
		log.fatal("Could not compile vertex shader.")

		app.running = false
		return
	}

	reload_shaders(app)
}

render_graph :: proc(app: ^App_State) 
{
	if app.coloring_method == .Use_Image {
		opengl.ActiveTexture(opengl.TEXTURE0)
		opengl.BindTexture(opengl.TEXTURE_2D, app.texture.id)
	}

	opengl.UseProgram(app.program)
	opengl.BindVertexArray(app.vao)
	opengl.ClearColor(0.1, 0.1, 0.1, 1)
	opengl.Clear(opengl.COLOR_BUFFER_BIT)
	opengl.DrawArrays(opengl.TRIANGLE_STRIP, 0, 4)
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
		opengl.ShaderSource(id, (i32)(len(sources)), raw_data(sources), raw_data(lengths))
		opengl.CompileShader(id)

		success: i32
		opengl.GetShaderiv(id, opengl.COMPILE_STATUS, &success)
		return id, (bool)(success)
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
		opengl.GetShaderInfoLog(fragment_shader_id, len(info_log), nil, ([^]u8)(&info_log))

		log.fatalf(
			"[compile_fragment_shader] Failed to compile fragment shader. Error msg: \"%s\"",
			info_log
		)
		sdl.ShowSimpleMessageBox(
			{.ERROR},
			"Failure!",
			fmt.ctprintf("Failed to compile fragment shader.\n\nError message: \"%s\"", info_log),
			app.window
		)

		app.running = false
		return
	}

	app.program, ok = opengl.create_and_link_program({app.vertex_shader_id, fragment_shader_id})

	if !ok {
		gl_err_msg, _ := opengl.get_last_error_message()
		log.fatalf(
			"[opengl.create_and_link_program] Failed to compile shader program. Error msg: \"%s\"",
			gl_err_msg,
		)
		sdl.ShowSimpleMessageBox(
			{.ERROR},
			"Failure!",
			fmt.ctprintf("Failed to compile shader program.\n\nError message: \"%s\"", gl_err_msg),
			app.window
		)

		app.running = false
		return
	}

	opengl.UseProgram(app.program)

	app.zoom.loc             = opengl.GetUniformLocation(app.program, "zoom")
	app.time.loc             = opengl.GetUniformLocation(app.program, "time")
	app.resolution.loc       = opengl.GetUniformLocation(app.program, "resolution")
	app.shift.loc            = opengl.GetUniformLocation(app.program, "shift")
	app.abcd.loc             = opengl.GetUniformLocation(app.program, "abcd")
	app.saturation.loc       = opengl.GetUniformLocation(app.program, "saturation")
	app.lightness.loc        = opengl.GetUniformLocation(app.program, "lightness")
	app.gamma_correction.loc = opengl.GetUniformLocation(app.program, "gamma_correction")

	width, height: i32
	sdl.GetWindowSizeInPixels(app.window, &width, &height)
	opengl.Viewport(0, 0, width, height)
	app.resolution.val = {(f32)(width), (f32)(height)}

	update_uniform(app.resolution)
	update_uniform(app.zoom)
	update_uniform(app.shift)
	update_uniform(app.time)
	update_uniform(app.time)
	update_uniform(app.gamma_correction)
	update_uniform(app.abcd)
	update_uniform(app.saturation)
	update_uniform(app.lightness)
}

update_uniform_single :: proc (uniform: Uniform(f32))
{
	opengl.Uniform1f(uniform.loc, uniform.val)
}

update_uniform_vec :: proc (uniform: Uniform([$L]f32))
{
	uniform := uniform

	switch L {
	case 1: opengl.Uniform1fv(uniform.loc, 1, ([^]f32)(&uniform.val))
	case 2: opengl.Uniform2fv(uniform.loc, 1, ([^]f32)(&uniform.val))
	case 3: opengl.Uniform3fv(uniform.loc, 1, ([^]f32)(&uniform.val))
	case 4: opengl.Uniform4fv(uniform.loc, 1, ([^]f32)(&uniform.val))
	case: unimplemented()
	}
}

update_uniform_2dvec :: proc (uniform: Uniform([$L1][$L2]f32))
{
	uniform := uniform

	switch L2 {
	case 1: opengl.Uniform1fv(uniform.loc, L1, ([^]f32)(&uniform.val))
	case 2: opengl.Uniform2fv(uniform.loc, L1, ([^]f32)(&uniform.val))
	case 3: opengl.Uniform3fv(uniform.loc, L1, ([^]f32)(&uniform.val))
	case 4: opengl.Uniform4fv(uniform.loc, L1, ([^]f32)(&uniform.val))
	case: unimplemented()
	}
}

update_uniform :: proc {
	update_uniform_single,
	update_uniform_vec,
	update_uniform_2dvec,
}

load_texture :: proc(app: ^App_State, img: ^Image_Data) 
{
	defer {
		img.is_resident = true
		log.infof("Uploaded %s image at \"%s\" onto GPU", img.size_str, img.filename)
	}

	opengl.DeleteTextures(1, &app.texture.id)
	opengl.GenTextures(1, &app.texture.id)
	opengl.BindTexture(opengl.TEXTURE_2D, app.texture.id)

	// https://stackoverflow.com/a/49126350
	opengl.PixelStorei(opengl.UNPACK_ALIGNMENT, 1)
	opengl.PixelStorei(opengl.UNPACK_ROW_LENGTH, 0)
	opengl.TexImage2D(
		opengl.TEXTURE_2D,
		0,
		opengl.RGB,
		img.size.x,
		img.size.y,
		0,
		opengl.RGB,
		opengl.UNSIGNED_BYTE,
		img.pixels,
	)
	set_tex_parameters(app.texture)
	opengl.GenerateMipmap(opengl.TEXTURE_2D)
}

set_tex_parameters :: proc(tex: Texture) 
{
	opengl.TexParameteri(opengl.TEXTURE_2D, opengl.TEXTURE_WRAP_S, tex.wrap_s)
	opengl.TexParameteri(opengl.TEXTURE_2D, opengl.TEXTURE_WRAP_T, tex.wrap_t)
	opengl.TexParameteri(opengl.TEXTURE_2D, opengl.TEXTURE_MIN_FILTER, tex.min_filter)
	opengl.TexParameteri(opengl.TEXTURE_2D, opengl.TEXTURE_MAG_FILTER, tex.mag_filter)
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
