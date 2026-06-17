#+feature using-stmt

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
}

Color :: [3]f32

// use uniform buffer object and a single "set_uniforms" proc?
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
// }

Uniforms :: struct {
	zoom:             i32,
	time:             i32,
	resolution:       i32,
	shift:            i32,
	abcd:             i32,
	gamma_correction: i32,
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
	if severity != opengl.DEBUG_SEVERITY_HIGH ||
	   severity != opengl.DEBUG_SEVERITY_MEDIUM {
		return
	}

	context = runtime.default_context()
	app := (^App_State)(user_param)

	fmt.println("[OpenGL] debug message:", message)
}

setup_gl :: proc(using app: ^App_State) 
{
	ctx = sdl.GL_CreateContext(window)
	if ctx == nil {
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

	sdl.GL_MakeCurrent(window, gl.ctx)

	opengl.load_up_to(
		GL_MAJOR_VERSION,
		GL_MINOR_VERSION,
		sdl.gl_set_proc_address,
	)

	when ODIN_DEBUG {
		opengl.DebugMessageCallback(debug_proc, app)
		opengl.Enable(opengl.DEBUG_OUTPUT)
		opengl.Enable(opengl.DEBUG_OUTPUT_SYNCHRONOUS)
	}

	width, height: i32
	sdl.GetWindowSizeInPixels(window, &width, &height)
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

	opengl.GenVertexArrays(1, &vao)
	opengl.BindVertexArray(vao)

	opengl.GenTextures(1, &texture)
	opengl.BindTexture(opengl.TEXTURE_2D, texture)

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
	vertex_shader_id, ok = opengl.compile_shader_from_source(
		VERTEX_SHADER,
		.VERTEX_SHADER,
	)
	if !ok {
		log.fatal("Could not compile vertex shader")
	}

	reload_shaders(app)
	opengl.Uniform1i(opengl.GetUniformLocation(program, "tex"), 0)
}

render_graph :: proc(using app: ^App_State) 
{
	opengl.UseProgram(program)
	opengl.BindVertexArray(vao)

	// Draw commands.
	opengl.ClearColor(0.1, 0.1, 0.1, 1)
	opengl.Clear(opengl.COLOR_BUFFER_BIT)

	opengl.DrawArrays(
		opengl.TRIANGLE_STRIP, // Draw triangles.
		0, // Begin drawing at index 0.
		4, // Use 4 indices.
	)
}

reload_shaders :: proc(using app: ^App_State) 
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
	opengl.DeleteProgram(program)

	@(static, rodata)
	coloring_method_headers := [Coloring_Method]cstring {
		.Use_HSL     = "#define USE_HSL\n",
		.Use_HSLuv   = "#define USE_HSLUV\n",
		.Use_Palette = "#define USE_PALETTE\n",
		.Use_Texture = "#define USE_TEXTURE\n",
	}

	// we all <3 pointer arithmetic!
	frag_ptr := transmute(uintptr)(FRAGMENT_SHADER)
	frag_wanted_part := transmute(cstring)(frag_ptr + 16)

	fragment_shader_id, ok := compile_fragment_shader(
		{
			"#version 300 es\n",
			coloring_method_headers[coloring_method],
			frag_wanted_part,
			translate(function),
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

		log.error(msg)
		sdl.ShowSimpleMessageBox({.ERROR}, "Failure!", msg, window)

		return
	}

	program, ok = opengl.create_and_link_program(
		{vertex_shader_id, fragment_shader_id},
	)

	if !ok {
		gl_err_msg, _ := opengl.get_last_error_message()
		msg := fmt.ctprintf(
			"[opengl.load_shaders_source] Failed to compile shader program. Error msg:\n\n\"%s\".",
			gl_err_msg,
		)

		log.error(msg)
		sdl.ShowSimpleMessageBox({.ERROR}, "Failure!", msg, window)

		return
	}

	opengl.UseProgram(program)

	uniforms = {
		zoom             = opengl.GetUniformLocation(program, "zoom"),
		time             = opengl.GetUniformLocation(program, "time"),
		resolution       = opengl.GetUniformLocation(program, "resolution"),
		shift            = opengl.GetUniformLocation(program, "shift"),
		abcd             = opengl.GetUniformLocation(program, "abcd"),
		gamma_correction = opengl.GetUniformLocation(
			program,
			"gamma_correction",
		),
	}

	width, height: i32
	sdl.GetWindowSizeInPixels(window, &width, &height)
	opengl.Viewport(0, 0, width, height)
	opengl.Uniform2f(uniforms.resolution, (f32)(width), (f32)(height))
	opengl.Uniform2f(uniforms.shift, shift.x, shift.y)
	opengl.Uniform1f(uniforms.zoom, zoom)
	opengl.Uniform1f(uniforms.time, time)
	opengl.Uniform1f(uniforms.gamma_correction, gamma_correction)
	opengl.Uniform3fv(uniforms.abcd, 4, ([^]f32)(&abcd))
}
