#+feature dynamic-literals
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

// three coloring modes:
//  1. predefined coloring functions for H, S, and L
//  2. user-provided coloring functions (HSL)
//  3. image (texture)
//  4. palette (https://iquilezles.org/articles/palettes/)

App_Context :: struct {
	window:   ^sdl.Window,
	renderer: ^sdl.Renderer,
	gl_ctx:   sdl.GLContext,
	vao:      u32,
	program:  u32,
	uniforms: map[string]i32,
	io:       ^imgui.IO,
	zoom:     f32,
	shift:    [2]f32,
	show_ui:  bool,
	function: []u8,
	err_msg:  string,
}

Coloring_Method :: enum u32 {
	Use_Default = 0,
	Use_Palette = 1,
	Use_Texture = 2,
	Use_User    = 3,
}

GL_MAJOR_VERSION :: 3
GL_MINOR_VERSION :: 3
vertex_shader :: #load("shaders/graph.vert", string)
fragment_shader :: #load("shaders/graph.frag", string)
pan_speed := (f32)(15)
zoom_speed := (f32)(1.1)

main :: proc() 
{
	context.logger = log.create_console_logger()

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
	}

	setup_sdl(&app)
	defer {
		sdl.GL_DestroyContext(gl_ctx)
		sdl.DestroyWindow(window)
		sdl.Quit()
	}

	setup_imgui(&app)
	defer {
		imgui_impl_opengl3.Shutdown()
		imgui_impl_sdl3.Shutdown()
		imgui.DestroyContext()
	}

	setup_gl(&app)
	defer {
		delete(uniforms)
		gl.DeleteProgram(program)
	}

	render_loop: for {
		event: sdl.Event
		for sdl.PollEvent(&event) {
			imgui_impl_sdl3.ProcessEvent(&event)

			if event.type == .QUIT {
				break render_loop
			}

			handle_event(&app, &event)
		}

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
	function = make([]u8, 1024)
	fmt.bprint(function, "z")
}

setup_sdl :: proc(using app: ^App_Context) 
{
	if !sdl.Init({.VIDEO}) {
		log.fatal("[sdl.Init]", sdl.GetError())
		sdl.Quit()
	}

	window = sdl.CreateWindow("Kolori", 800, 600, {.OPENGL, .RESIZABLE})
	if window == nil {
		log.fatal("[sdl.CreateWindow]", sdl.GetError())
		sdl.Quit()
	}
	sdl.SetHint(sdl.HINT_TOUCH_MOUSE_EVENTS, "true")
	sdl.SetWindowPosition(
		window,
		sdl.WINDOWPOS_CENTERED,
		sdl.WINDOWPOS_CENTERED,
	)
	sdl.ShowWindow(window)

	gl_ctx = sdl.GL_CreateContext(window)
	if gl_ctx == nil {
		log.fatal("[sdl.GL_CreateContext]", sdl.GetError())
		sdl.Quit()
	}
}

setup_imgui :: proc(using app: ^App_Context) 
{
	imgui.CHECKVERSION()
	imgui.CreateContext()

	io = imgui.GetIO()
	io.ConfigFlags += {.NavEnableKeyboard, .DockingEnable}

	imgui_impl_sdl3.InitForOpenGL(window, gl_ctx)
	imgui_impl_opengl3.Init("#version 330 core")
	imgui.StyleColorsDark()
}

setup_gl :: proc(using app: ^App_Context) 
{
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
	program, ok = gl.load_shaders_source(
		vertex_shader,
		strings.concatenate(
			{fragment_shader, "\n\n", translate(function)},
			context.temp_allocator,
		),
	)

	if !ok {
		log.fatal("[gl.load_shaders_source]", gl.get_last_error_message())
		sdl.Quit()
	}

	gl.UseProgram(program)

	uniforms = {
		"zoom"            = gl.GetUniformLocation(program, "zoom"),
		"resolution"      = gl.GetUniformLocation(program, "resolution"),
		"shift"           = gl.GetUniformLocation(program, "shift"),
		"coloring_method" = gl.GetUniformLocation(program, "coloring_method"),
		"texture"         = gl.GetUniformLocation(program, "texture"),
	}

	gl.Uniform1i(uniforms["texture"], 0)
	gl.Uniform1f(uniforms["zoom"], 1)
	gl.Uniform2i(uniforms["resolution"], width, height)
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
		gl.Uniform2i(uniforms["resolution"], width, height)
	case .KEY_DOWN:
		if io.WantCaptureKeyboard {
			break
		}

		width, height: i32
		sdl.GetWindowSizeInPixels(window, &width, &height)

		scale := [2]f32{(f32)(width), (f32)(height)}
		direction: [2]f32

		switch event.key.key {
		case sdl.K_F12:
			pixels := make([]u8, width * height * 3, context.temp_allocator)
			gl.ReadBuffer(gl.BACK)
			gl.PixelStorei(gl.PACK_ALIGNMENT, 1)
			gl.ReadPixels(0, 0, width, height, gl.RGB, gl.UNSIGNED_BYTE, raw_data(pixels))
			
			surface := sdl.CreateSurfaceFrom(width, height, .RGB24, raw_data(pixels), width * 3)
			sdl.FlipSurface(surface, .VERTICAL)
			defer sdl.DestroySurface(surface)

			buf := make([]u8, 17, context.temp_allocator)
			filename := fmt.tprintf("kolori_screenshot%s.png", now_to_string(buf))
			sdl.SavePNG(surface, (cstring)(raw_data(filename)))
		case sdl.K_F11:
			is_fullscreen := .FULLSCREEN in sdl.GetWindowFlags(window)
			sdl.SetWindowFullscreen(window, !is_fullscreen)
			sdl.SyncWindow(window)
		case sdl.K_R:
			reload_shaders(app)
		case sdl.K_ESCAPE:
			zoom = 1
			shift = {0, 0}
		case sdl.K_H: show_ui = !show_ui
		case sdl.K_X, sdl.K_MINUS: zoom *= zoom_speed
		case sdl.K_C, sdl.K_EQUALS: zoom /= zoom_speed
		case sdl.K_W, sdl.K_UP: direction = [2]f32{0, 1}
		case sdl.K_A, sdl.K_LEFT: direction = [2]f32{-1, 0}
		case sdl.K_S, sdl.K_DOWN: direction = [2]f32{0, -1}
		case sdl.K_D, sdl.K_RIGHT: direction = [2]f32{1, 0}
		}

		shift += (pan_speed * direction / scale) * (zoom * 2)
		gl.Uniform2f(uniforms["shift"], shift.x, shift.y)
		gl.Uniform1f(uniforms["zoom"], zoom)
	case .MOUSE_WHEEL:
		if io.WantCaptureMouse {
			break
		}

		if event.wheel.y < 0 {
			zoom *= zoom_speed
		} else if event.wheel.y > 0 {
			zoom /= zoom_speed
		}

		gl.Uniform1f(uniforms["zoom"], zoom)
	case .MOUSE_MOTION:
		if io.WantCaptureMouse {
			break
		}

		if .LEFT in event.motion.state {
			width, height: i32
			sdl.GetWindowSizeInPixels(window, &width, &height)

			motion := [2]f32{event.motion.xrel, event.motion.yrel}
			scale := [2]f32{(f32)(-width), (f32)(height)}
			shift += (motion / scale) * zoom

			gl.Uniform2f(uniforms["shift"], shift.x, shift.y)
		}
	}

	now_to_string :: proc(buf: []u8) -> string
	{
		// dd-mm-yyyy
		y, _month, d := time.date(time.now())
		month := (u8)(_month)

		buf[9] = '0' + (u8)(y % 10); y /= 10
		buf[8] = '0' + (u8)(y % 10); y /= 10
		buf[7] = '0' + (u8)(y % 10); y /= 10
		buf[6] = '0' + (u8)(y)
		buf[5] = '-'
		buf[4] = '0' + (u8)(month % 10); month /= 10
		buf[3] = '0' + (u8)(month % 10)
		buf[2] = '-'
		buf[1] = '0' + (u8)(d % 10); d /= 10
		buf[0] = '0' + (u8)(d % 10)

		// sep
		buf[10] = '_'

		// hhmmss
		h, minute, s := time.clock(time.now())

		buf[16] = '0' + (u8)(s % 10); s /= 10
		buf[15] = '0' + (u8)(s)
		buf[14] = '0' + (u8)(minute % 10); minute /= 10
		buf[13] = '0' + (u8)(minute)
		buf[12] = '0' + (u8)(h % 10); h /= 10
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

draw_ui :: proc(using app: ^App_Context) 
{
	if !show_ui {
		return
	}

	imgui_impl_opengl3.NewFrame()
	imgui_impl_sdl3.NewFrame()
	imgui.NewFrame()

	// imgui.ShowDemoWindow()
	// imgui.ShowUserGuide()

	imgui.Begin("Settings")
	{
		if imgui.InputText(
			"Function",
			(cstring)(raw_data(function)),
			1024,
			{.EnterReturnsTrue},
		) {
			result, ok := translate(function)
			if !ok {
				imgui.OpenPopup("Error")
				err_msg = strings.clone(result)
				log.error(err_msg)
			} else {
				reload_shaders(app)
			}
		}

		if imgui.BeginPopupModal("Error") {
			imgui.Text((cstring)(raw_data(err_msg)))
			if imgui.Button("Close") {
				delete(err_msg)
				imgui.CloseCurrentPopup()
			}

			imgui.EndPopup()
		}

	}
	imgui.End()

	imgui.Render()
	imgui_impl_opengl3.RenderDrawData(imgui.GetDrawData())
}

reload_shaders :: proc(using app: ^App_Context)
{
	ok: bool
	program, ok = gl.load_shaders_source(
		vertex_shader,
		strings.concatenate(
			{fragment_shader, "\n\n", translate(function)},
			context.temp_allocator,
		),
	)

	if !ok {
		log.fatal("[gl.load_shaders_source]", gl.get_last_error_message())
		sdl.Quit()
	}

	gl.UseProgram(program)

	uniforms = {
		"zoom"            = gl.GetUniformLocation(program, "zoom"),
		"resolution"      = gl.GetUniformLocation(program, "resolution"),
		"shift"           = gl.GetUniformLocation(program, "shift"),
		"coloring_method" = gl.GetUniformLocation(
			program,
			"coloring_method",
		),
		"texture"         = gl.GetUniformLocation(program, "texture"),
	}

	width, height: i32
	sdl.GetWindowSize(window, &width, &height)
	gl.Viewport(0, 0, width, height)
	gl.Uniform2i(uniforms["resolution"], width, height)
	gl.Uniform2f(uniforms["shift"], shift.x, shift.y)
	gl.Uniform1f(uniforms["zoom"], zoom)

	render_graph(app)
	sdl.GL_SwapWindow(window)
}
