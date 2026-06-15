#+feature using-stmt

package kolori

import "odin-imgui/imgui_impl_opengl3"
import "odin-imgui/imgui_impl_sdl3"
import imgui "odin-imgui"
import gl "vendor:OpenGL"
import sdl "vendor:sdl3"
import "core:strings"
import "core:time"
import "core:log"
import "core:fmt"
import "core:mem"

// four coloring modes:
//  1. predefined coloring functions for H, S, and L
//  2. user-provided coloring functions (HSL)
//  3. image (texture)
//  4. palette (https://iquilezles.org/articles/palettes/)

App_Context :: struct {
	window:           ^sdl.Window,
	gl_ctx:           sdl.GLContext,
	vao:              u32,
	program:          u32,
	vertex_shader_id: u32,
	texture:          u32,
	coloring_method:  Coloring_Method,
	uniforms:         Uniforms,
	io:               ^imgui.IO,
	math_font:        ^imgui.Font,
	function:         cstring,
	err_msg:          cstring,
	time_speed:       f32,
	animation_paused: bool,
	show_ui:          bool,
	tex:              u32,
	zoom:             f32,
	time:             f32,
	/* */
	shift:            [2]f32,
	/* */
	abcd:			  [4][3]f32,
	gamma_correction: f32,
}

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
// 	abcd:             Uniform([4][3]f32),
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

Coloring_Method :: enum i32 {
	Use_Default,
	Use_Texture,
	Use_Palette,
	// Use_User,
}

GL_MAJOR_VERSION :: 3
GL_MINOR_VERSION :: 3
@(rodata) VERTEX_SHADER := #load("shaders/graph.vert", string)
@(rodata) FRAGMENT_SHADER := #load("shaders/graph.frag", cstring)
PAN_SPEED :: (f32)(15)
ZOOM_SPEED :: (f32)(1.1)

main :: proc() 
{
	context.logger = log.create_console_logger()
	context.logger.lowest_level = ODIN_DEBUG ? .Debug : .Info
	defer log.destroy_console_logger(context.logger)

	when ODIN_DEBUG {
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		context.allocator = mem.tracking_allocator(&track)

		defer {
			if len(track.allocation_map) > 0 {
				fmt.eprintf(
					"=== %v allocations not freed: ===\n",
					len(track.allocation_map),
				)
				for _, entry in track.allocation_map {
					fmt.eprintf(
						"- %v bytes @ %v\n",
						entry.size,
						entry.location,
					)
				}
			}
			mem.tracking_allocator_destroy(&track)
		}
	}

	using app: App_Context
	setup_app(&app)
	defer {
		delete(function)
		delete(err_msg)
	}

	setup_sdl(&app)
	defer {
		sdl.GL_DestroyContext(gl_ctx)
		sdl.DestroyWindow(window)
		sdl.Quit()
	}

	setup_gl(&app)
	defer {
		gl.DeleteShader(vertex_shader_id)
		gl.DeleteProgram(program)
	}

	setup_imgui(&app)
	defer {
		imgui_impl_opengl3.Shutdown()
		imgui_impl_sdl3.Shutdown()
		imgui.DestroyContext()
	}

	last_time := sdl.GetTicks()
	render_loop: for {
		event: sdl.Event
		for sdl.PollEvent(&event) {
			imgui_impl_sdl3.ProcessEvent(&event)

			if event.type == .QUIT {
				break render_loop
			}

			handle_event(&app, &event)
		}

		if !animation_paused {
			time += (f32)(sdl.GetTicks() - last_time)
			gl.Uniform1f(uniforms.time, time * 1e-3 * time_speed)
		}
		last_time = sdl.GetTicks()

		render_graph(&app)
		draw_ui(&app)

		sdl.GL_SwapWindow(window)
		free_all(context.temp_allocator)
	}
}

setup_app :: proc(using app: ^App_Context) 
{
	zoom = 1
	show_ui = true
	time_speed = 1
	gamma_correction = 0.65
	coloring_method = .Use_Texture
	err_msg = strings.clone_to_cstring("")
	function = (cstring)(make([^]u8, 1024))
	([^]u8)(function)[0] = 'z'
}

setup_sdl :: proc(using app: ^App_Context) 
{
	if !sdl.Init({.VIDEO}) {
		log.fatal("[sdl.Init]", sdl.GetError())
		sdl.Quit()
	}

	window = sdl.CreateWindow("Kolori", 800, 600, {.OPENGL, .RESIZABLE, .HIGH_PIXEL_DENSITY})
	if window == nil {
		log.fatal("[sdl.CreateWindow]", sdl.GetError())
		sdl.Quit()
	}
	sdl.SetWindowPosition(
		window,
		sdl.WINDOWPOS_CENTERED,
		sdl.WINDOWPOS_CENTERED,
	)
	sdl.ShowWindow(window)
}

setup_gl :: proc(using app: ^App_Context) 
{
	gl_ctx = sdl.GL_CreateContext(window)
	if gl_ctx == nil {
		log.fatal("[sdl.GL_CreateContext]", sdl.GetError())
		sdl.Quit()
	}

	context_flags: sdl.GLContextFlag
	when ODIN_DEBUG {context_flags |= sdl.GL_CONTEXT_DEBUG_FLAG}
	when ODIN_OS == .Darwin {context_flags |= sdl.GL_CONTEXT_FORWARD_COMPATIBLE_FLAG}

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

	sdl.GL_SetSwapInterval(1)

	sdl.GL_MakeCurrent(window, gl_ctx)

	gl.load_up_to(GL_MAJOR_VERSION, GL_MINOR_VERSION, sdl.gl_set_proc_address)

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

handle_event :: proc(using app: ^App_Context, event: ^sdl.Event) 
{
	gl.UseProgram(program)

	#partial switch event.type {
	// todo(touchscreens) support pinching motions for zoom in/out 

	case .WINDOW_RESIZED:
		width, height: i32
		sdl.GetWindowSizeInPixels(window, &width, &height)
		gl.Viewport(0, 0, width, height)
		gl.Uniform2i(uniforms.resolution, width, height)
	case .KEY_DOWN:
		if io.WantCaptureKeyboard {
			break
		}

		width, height: i32
		sdl.GetWindowSizeInPixels(window, &width, &height)

		scale := (f32)(min(width, height))
		direction: [2]f32

		switch event.key.key {
		case sdl.K_F12:
			pixels := make([]u8, width * height * 3, context.temp_allocator)
			gl.ReadBuffer(gl.BACK)
			gl.PixelStorei(gl.PACK_ALIGNMENT, 1)
			gl.ReadPixels(
				0,
				0,
				width,
				height,
				gl.RGB,
				gl.UNSIGNED_BYTE,
				raw_data(pixels),
			)

			surface := sdl.CreateSurfaceFrom(
				width,
				height,
				.RGB24,
				raw_data(pixels),
				width * 3,
			)
			sdl.FlipSurface(surface, .VERTICAL)
			defer sdl.DestroySurface(surface)

			buf: [17]u8
			filename := fmt.tprintf(
				"kolori_screenshot%s.png",
				now_to_string(buf[:]),
			)
			ok := sdl.SavePNG(surface, (cstring)(raw_data(filename)))
			if ok {
				log.info("Saved screenshot to", filename)
			} else {
				log.error("[sdl.SavePNG] Failed to save screenshot")
			}
		case sdl.K_F11:
			is_fullscreen := .FULLSCREEN in sdl.GetWindowFlags(window)
			sdl.SetWindowFullscreen(window, !is_fullscreen)
			sdl.SyncWindow(window)
		case sdl.K_ESCAPE:
			zoom = 1
			shift = {0, 0}
		case sdl.K_R:
			reload_shaders(app)
		case sdl.K_C:
			if sdl.CursorVisible() {
				ok := sdl.HideCursor()
				if !ok {
					log.error("[sdl.HideCursor] Failed to hide cursor")
				}
			} else {
				ok := sdl.ShowCursor()
				if !ok {
					log.error("[sdl.ShowCursor] Failed to show cursor")
				}
			}
		case sdl.K_P: animation_paused = !animation_paused
		case sdl.K_H: show_ui = !show_ui
		case sdl.K_Z, sdl.K_MINUS: zoom *= ZOOM_SPEED
		case sdl.K_X, sdl.K_EQUALS: zoom /= ZOOM_SPEED
		case sdl.K_W, sdl.K_UP: direction = [2]f32{0, 1}
		case sdl.K_A, sdl.K_LEFT: direction = [2]f32{-1, 0}
		case sdl.K_S, sdl.K_DOWN: direction = [2]f32{0, -1}
		case sdl.K_D, sdl.K_RIGHT: direction = [2]f32{1, 0}
		}

		shift += (PAN_SPEED * direction / scale) * (zoom * 2)
		gl.Uniform2f(uniforms.shift, shift.x, shift.y)
		gl.Uniform1f(uniforms.zoom, zoom)
	case .MOUSE_WHEEL:
		if io.WantCaptureMouse {
			break
		}

		if event.wheel.y < 0 {
			zoom *= ZOOM_SPEED
		} else if event.wheel.y > 0 {
			// width, height: i32
			// sdl.GetWindowSize(window, &width, &height)

			// resolution := [2]f32{(f32)(width), (f32)(height)}

			// mouse_pos := [2]f32{event.wheel.mouse_x, event.wheel.mouse_y} 
			// pan_velocity := (mouse_pos - resolution * 0.5) * {1, -1}
			// pan_velocity = pan_velocity / resolution / zoom
			// shift += pan_velocity

			// gl.Uniform2f(uniforms["shift"], shift.x, shift.y)
			zoom /= ZOOM_SPEED
		}


		gl.Uniform1f(uniforms.zoom, zoom)
	case .MOUSE_MOTION:
		if io.WantCaptureMouse {
			break
		}

		if .LEFT in event.motion.state {
			width, height: i32
			sdl.GetWindowSizeInPixels(window, &width, &height)

			motion := [2]f32{-event.motion.xrel, event.motion.yrel}
			scale := (f32)(min(width, height))
			shift += (motion / scale) * zoom

			gl.Uniform2f(uniforms.shift, shift.x, shift.y)
		}
	}

	now_to_string :: proc(buf: []u8) -> string 
	{
		now := time.now()

		// dd-mm-yyyy
		y, _month, d := time.date(now)
		month := (u8)(_month)

		buf[9] = '0' + (u8)(y % 10);y /= 10
		buf[8] = '0' + (u8)(y % 10);y /= 10
		buf[7] = '0' + (u8)(y % 10);y /= 10
		buf[6] = '0' + (u8)(y)
		buf[5] = '-'
		buf[4] = '0' + (u8)(month % 10);month /= 10
		buf[3] = '0' + (u8)(month % 10)
		buf[2] = '-'
		buf[1] = '0' + (u8)(d % 10);d /= 10
		buf[0] = '0' + (u8)(d % 10)

		// sep
		buf[10] = '_'

		// hhmmss
		h, minute, s := time.clock(now)

		buf[16] = '0' + (u8)(s % 10);s /= 10
		buf[15] = '0' + (u8)(s)
		buf[14] = '0' + (u8)(minute % 10);minute /= 10
		buf[13] = '0' + (u8)(minute)
		buf[12] = '0' + (u8)(h % 10);h /= 10
		buf[11] = '0' + (u8)(h)

		return (string)(buf[:16])
	}
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
		lengths := make([dynamic]i32, 0, len(sources))
		defer delete(lengths)
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
	gl.Uniform3fv(uniforms.abcd, 4, ([^]f32)(&abcd[0]))
}
