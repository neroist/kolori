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
	uniforms:         struct {
		zoom:            i32,
		time:            i32,
		resolution:      i32,
		shift:           i32,
		coloring_method: i32,
		texture:         i32,
	},
	io:               ^imgui.IO,
	math_font:        ^imgui.Font,
	zoom:             f32,
	shift:            [2]f32,
	show_ui:          bool,
	function:         cstring,
	err_msg:          cstring,
	time:             f32,
	time_speed:       f32,
	animation_paused: bool,
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
		delete(err_msg)
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
		gl.DeleteProgram(program)
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

	imgui.FontAtlas_AddFontFromFileTTF(io.Fonts, "DMSans.ttf", 18)
	math_font = imgui.FontAtlas_AddFontFromFileTTF(io.Fonts, "DMSans.ttf", 18)

	style := imgui.GetStyle()
	style.WindowRounding = 8
	style.ChildRounding = 8
	style.PopupRounding = 6
	style.FrameRounding = 6
	style.ScrollbarRounding = 6
	style.GrabRounding = 6
	style.TabRounding = 6
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

	reload_shaders(app)
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

		scale := [2]f32{(f32)(width), (f32)(height)}
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
		case sdl.K_Z, sdl.K_MINUS: zoom *= zoom_speed
		case sdl.K_X, sdl.K_EQUALS: zoom /= zoom_speed
		case sdl.K_W, sdl.K_UP: direction = [2]f32{0, 1}
		case sdl.K_A, sdl.K_LEFT: direction = [2]f32{-1, 0}
		case sdl.K_S, sdl.K_DOWN: direction = [2]f32{0, -1}
		case sdl.K_D, sdl.K_RIGHT: direction = [2]f32{1, 0}
		}

		shift += (pan_speed * direction / scale) * (zoom * 2)
		gl.Uniform2f(uniforms.shift, shift.x, shift.y)
		gl.Uniform1f(uniforms.zoom, zoom)
	case .MOUSE_WHEEL:
		if io.WantCaptureMouse {
			break
		}

		if event.wheel.y < 0 {
			zoom *= zoom_speed
		} else if event.wheel.y > 0 {
			// width, height: i32
			// sdl.GetWindowSize(window, &width, &height)

			// resolution := [2]f32{(f32)(width), (f32)(height)}

			// mouse_pos := [2]f32{event.wheel.mouse_x, event.wheel.mouse_y} 
			// pan_velocity := (mouse_pos - resolution * 0.5) * {1, -1}
			// pan_velocity = pan_velocity / resolution / zoom
			// shift += pan_velocity

			// gl.Uniform2f(uniforms["shift"], shift.x, shift.y)
			zoom /= zoom_speed
		}


		gl.Uniform1f(uniforms.zoom, zoom)
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

			gl.Uniform2f(uniforms.shift, shift.x, shift.y)
		}
	}

	now_to_string :: proc(buf: []u8) -> string 
	{
		// dd-mm-yyyy
		y, _month, d := time.date(time.now())
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
		h, minute, s := time.clock(time.now())

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

	imgui.SetNextWindowBgAlpha(0.35)

	imgui.Begin("Plotter", flags = {.AlwaysAutoResize})
	imgui.PushFontFloat(math_font, 22.5)
	imgui.Text("f(z) =")
	imgui.PopFont()
	imgui.SameLine()

	if imgui.InputText("##", function, 1024) && len(function) > 0 {
		delete(err_msg)
		err, failure := validate(function).?

		err_msg = strings.clone_to_cstring(failure ? err : "")

		if !failure {
			time = 0
			animation_paused = false
			reload_shaders(app)
		}
	}
	imgui.PushStyleColorImVec4(.Text, [4]f32{255, 0, 0, 255})
	imgui.TextWrapped(err_msg)
	imgui.PopStyleColor()

	if imgui.CollapsingHeader("Animation Settings", {.DefaultOpen}) {
		imgui.SliderFloat("Anim. speed", &time_speed, 0.1, 10)
		imgui.Checkbox("Pause Anim.", &animation_paused)
		if imgui.Button("Reset Anim.") {
			time = 0
			animation_paused = false
		}
	}
	imgui.End()

	imgui.Render()
	imgui_impl_opengl3.RenderDrawData(imgui.GetDrawData())
}

reload_shaders :: proc(using app: ^App_Context) 
{
	gl.UseProgram(0)
	gl.DeleteProgram(program)

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
		zoom            = gl.GetUniformLocation(program, "zoom"),
		time            = gl.GetUniformLocation(program, "time"),
		resolution      = gl.GetUniformLocation(program, "resolution"),
		shift           = gl.GetUniformLocation(program, "shift"),
		coloring_method = gl.GetUniformLocation(program, "coloring_method"),
		texture         = gl.GetUniformLocation(program, "texture"),
	}

	width, height: i32
	sdl.GetWindowSizeInPixels(window, &width, &height)
	gl.Viewport(0, 0, width, height)
	gl.Uniform2i(uniforms.resolution, width, height)
	gl.Uniform2f(uniforms.shift, shift.x, shift.y)
	gl.Uniform1f(uniforms.zoom, zoom)
	gl.Uniform1f(uniforms.time, time)
}
