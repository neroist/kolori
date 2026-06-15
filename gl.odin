#+feature using-stmt

package kolori

import gl "vendor:OpenGL"
import sdl "vendor:sdl3"
import "base:runtime"
import "core:log"
import "core:fmt"

debug_proc :: proc "c" (source: u32, type: u32, id: u32, severity: u32, length: i32, message: cstring, user_param: rawptr)
{
	if severity != gl.DEBUG_SEVERITY_HIGH || severity != gl.DEBUG_SEVERITY_MEDIUM {
		return
	}

	context = runtime.default_context()
	app := (^App_Context)(user_param)

	fmt.println("[OpenGL] debug message:", message)
}

setup_gl :: proc(using app: ^App_Context) 
{
	gl_ctx = sdl.GL_CreateContext(window)
	if gl_ctx == nil {
		log.fatal("[sdl.GL_CreateContext]", sdl.GetError())
		sdl.Quit()
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
	sdl.GL_SetSwapInterval(0)

	sdl.GL_MakeCurrent(window, gl_ctx)

	gl.load_up_to(GL_MAJOR_VERSION, GL_MINOR_VERSION, sdl.gl_set_proc_address)

	when ODIN_DEBUG {
		gl.DebugMessageCallback(debug_proc, app)
		gl.Enable(gl.DEBUG_OUTPUT)
		gl.Enable(gl.DEBUG_OUTPUT_SYNCHRONOUS)
	}

	width, height: i32
	sdl.GetWindowSizeInPixels(window, &width, &height)
	gl.Viewport(0, 0, width, height)

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

	gl.GenVertexArrays(1, &vao)
	gl.BindVertexArray(vao)

	gl.GenTextures(1, &texture)
	gl.BindTexture(gl.TEXTURE_2D, texture)

	vbo: u32
	gl.GenBuffers(1, &vbo)
	gl.BindBuffer(gl.ARRAY_BUFFER, vbo)

	gl.BufferData(
		gl.ARRAY_BUFFER, // target
		size_of(vertices), // size of the buffer object's data store
		&vertices, // data used for initialization
		gl.STATIC_DRAW, // usage
	)

	gl.VertexAttribPointer(
		0, // index
		2, // size
		gl.FLOAT, // type
		gl.FALSE, // normalized
		2 * size_of(f32), // stride
		0, // offset
	)

	gl.EnableVertexAttribArray(0)

	ok: bool
	vertex_shader_id, ok = gl.compile_shader_from_source(VERTEX_SHADER, .VERTEX_SHADER)
	if !ok {
		log.fatal("Could not compile vertex shader")
	}

	reload_shaders(app)
	gl.Uniform1i(gl.GetUniformLocation(program, "tex"), 0)
}

render_graph :: proc(using app: ^App_Context) 
{
	gl.UseProgram(program)
	gl.BindVertexArray(vao)

	// Draw commands.
	gl.ClearColor(0.1, 0.1, 0.1, 1)
	gl.Clear(gl.COLOR_BUFFER_BIT)

	gl.DrawArrays(
		gl.TRIANGLE_STRIP, // Draw triangles.
		0, // Begin drawing at index 0.
		4, // Use 4 indices.
	)
}

reload_shaders :: proc(using app: ^App_Context) 
{
	compile_fragment_shader :: proc (sources: []cstring) -> (id: u32, ok: bool)
	{
		lengths := make([dynamic]i32, 0, len(sources), context.temp_allocator)
		for i in sources {
			append(&lengths, (i32)(len(i)))
		}
		
		id = gl.CreateShader(gl.FRAGMENT_SHADER)
		gl.ShaderSource(
			id,
			(i32)(len(sources)),
			raw_data(sources),
			raw_data(lengths)
		)
		gl.CompileShader(id)

		success: i32
		info_log: [512]u8
		gl.GetShaderiv(id, gl.COMPILE_STATUS, &success)
		if success == 0 {
			gl.GetShaderInfoLog(id, len(info_log), nil, ([^]u8)(&info_log))
			log.errorf("Failed to compile fragment shader: %s", info_log)
			return 0, false
		}

		return id, true
	}

	gl.UseProgram(0)
	gl.DeleteProgram(program)

	@(static, rodata)
	coloring_method_headers := [Coloring_Method]cstring{
		.Use_Default = "#define USE_DEFAULT\n",
		.Use_Palette = "#define USE_PALETTE\n",
		.Use_Texture = "#define USE_TEXTURE\n"
	}

	// we all <3 pointer arithmetic!
	frag_ptr := transmute(uintptr)(FRAGMENT_SHADER)
	frag_wanted_part := transmute(cstring)(frag_ptr + 17)

	fragment_shader_id, ok := compile_fragment_shader({
		"#version 330 core\n",
		coloring_method_headers[coloring_method],
		frag_wanted_part,
		translate(function)
	})
	defer gl.DeleteShader(fragment_shader_id)
	if !ok {
		sdl.Quit()
	}

	program, ok = gl.create_and_link_program({vertex_shader_id, fragment_shader_id})

	if !ok {
		log.error(
			"[gl.load_shaders_source] Failed to compile shader progam. Error msg:",
			gl.get_last_error_message()
		)
		sdl.Quit()
	}

	gl.UseProgram(program)

	uniforms = {
		zoom             = gl.GetUniformLocation(program, "zoom"),
		time             = gl.GetUniformLocation(program, "time"),
		resolution       = gl.GetUniformLocation(program, "resolution"),
		shift            = gl.GetUniformLocation(program, "shift"),
		abcd             = gl.GetUniformLocation(program, "abcd"),
		gamma_correction = gl.GetUniformLocation(program, "gamma_correction")
	}

	width, height: i32
	sdl.GetWindowSizeInPixels(window, &width, &height)
	gl.Viewport(0, 0, width, height)
	gl.Uniform2i(uniforms.resolution, width, height)
	gl.Uniform2f(uniforms.shift, shift.x, shift.y)
	gl.Uniform1f(uniforms.zoom, zoom)
	gl.Uniform1f(uniforms.time, time)
	gl.Uniform1f(uniforms.gamma_correction, gamma_correction)
	gl.Uniform3fv(uniforms.abcd, 4, ([^]f32)(&abcd))
}
