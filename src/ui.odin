package kolori

import "../odin-imgui/imgui_impl_opengl3"
import "../odin-imgui/imgui_impl_sdl3"
import stbi "vendor:stb/image"
import opengl "vendor:OpenGL"
import imgui "../odin-imgui"
import sdl "vendor:sdl3"
import "core:math/rand"
import "base:runtime"
import "core:math"
import "core:fmt"
import "core:log"

Ui_State :: struct {
	window:           ^sdl.Window,
	window_icon:      ^sdl.Surface,
	io:               ^imgui.IO,
	math_font:        ^imgui.Font,
	function:         cstring,
	err_msg:          cstring,
	coloring_method:  Coloring_Method,
	time_speed:       f32,
	main_scale:       f32,
	framerate:        i32,
	animation_paused: bool,
	show_ui:          bool,
	vsync:            bool,
}

Coloring_Method :: enum i32 {
	Use_HSL,
	Use_HSLuv,
	Use_Palette,
	Use_Texture,
}

IMGUI_CONFIG_FLAGS :: imgui.ConfigFlags{.NavEnableKeyboard, .DockingEnable}
APP_ICON_DATA :: #load("../favicon/favicon-64x64.png", []u8)
MAIN_FONT_DATA :: #load("../fonts/DMSans.ttf", []u8)
MAX_FRAMERATE :: 260

setup_sdl :: proc(app: ^App_State) 
{
	_ = sdl.SetAppMetadata("Kolori", "0.2.0", "com.neroist.kolori")
	_ = sdl.SetAppMetadataProperty(
		sdl.PROP_APP_METADATA_URL_STRING,
		"https://github.com/neroist/kolori",
	)

	if !sdl.Init({.VIDEO}) {
		log.fatal(
			"[sdl.Init] Failed to initialize SDL3. Error msg:",
			sdl.GetError(),
		)

		app.running = false
		return
	}

	primary_display := sdl.GetPrimaryDisplay()
	app.main_scale = sdl.GetDisplayContentScale(primary_display)
	if app.main_scale == 0 {
		app.main_scale = 1
	}

	window_flags := sdl.WindowFlags{.OPENGL, .RESIZABLE, .HIDDEN, .HIGH_PIXEL_DENSITY}
	app.window = sdl.CreateWindow(
		"Kolori, from Stardance <3",
		(i32)(800 * app.main_scale),
		(i32)(600 * app.main_scale),
		window_flags,
	)
	if app.window == nil {
		log.fatal(
			"[sdl.CreateWindow] Failed to create window. Error msg:",
			sdl.GetError(),
		)

		app.running = false
		return
	}

	stream := sdl.IOFromMem(raw_data(APP_ICON_DATA), len(APP_ICON_DATA))
	app.window_icon = sdl.LoadPNG_IO(stream, true)
	sdl.SetWindowIcon(app.window, app.window_icon)

	sdl.SetWindowPosition(
		app.window,
		sdl.WINDOWPOS_CENTERED,
		sdl.WINDOWPOS_CENTERED,
	)
	sdl.ShowWindow(app.window)
}

setup_imgui :: proc(app: ^App_State) 
{
	imgui.CreateContext()
	imgui_impl_opengl3.Init("#version 300 es")
	imgui_impl_sdl3.InitForOpenGL(app.window, app.gl.ctx)

	app.io = imgui.GetIO()
	app.io.ConfigFlags += IMGUI_CONFIG_FLAGS

	// the ui is too big, scale it down some
	style_imgui(app.main_scale * 0.8)

	// these are simply the defaults as described in `imgui.odin`
	font_cfg := imgui.FontConfig{
		FontDataOwnedByAtlas = false,
		ExtraSizeScale = 1,
		GlyphMaxAdvanceX = math.F32_MAX,
		RasterizerMultiply = 1,
		RasterizerDensity = 1,
	}

	// this will also be used as the main ui font,
	// as it is the first font loaded
	app.math_font = imgui.FontAtlas_AddFontFromMemoryTTF(
		app.io.Fonts,
		raw_data(MAIN_FONT_DATA),
		(i32)(len(MAIN_FONT_DATA)),
		18,
		&font_cfg
	)
}

style_imgui :: proc(scale: f32 = 1) 
{
	style := imgui.GetStyle()
	
	imgui.Style_ScaleAllSizes(style, scale)
	style.FontScaleDpi = scale

	imgui.StyleColorsDark(style)
	style.WindowRounding = 8
	style.ChildRounding = 8
	style.PopupRounding = 6
	style.FrameRounding = 6
	style.ScrollbarRounding = 6
	style.GrabRounding = 6
	style.TabRounding = 6
}

draw_ui :: proc(app: ^App_State) 
{
	if !app.show_ui {
		return
	}

	imgui_impl_opengl3.NewFrame()
	imgui_impl_sdl3.NewFrame()
	imgui.NewFrame()

	imgui.SetNextWindowBgAlpha(0.35)

	imgui.Begin("Plotter", flags = {.AlwaysAutoResize})
		function_input(app)
		animation_settings(app)
		coloring_settings(app)
	imgui.End()

	imgui.Render()
	imgui_impl_opengl3.RenderDrawData(imgui.GetDrawData())
}

function_input :: proc(app: ^App_State)
{
	@(static) failure: bool

	imgui.PushFontFloat(app.math_font, 22)
	imgui.Text("f(z) =")
	imgui.PopFont()

	imgui.SameLine()

	if imgui.InputText("##function", app.function, FUNCTION_BUF_SIZE) {
		err: cstring
		err, failure = validate(app.function).?

		// simply `err != err_msg` as a predicate compiles
		// when `err` is nil and `err_msg` is a string.
		// what does that even do?
		if !failure {
			// if the function hasn't changed since 
			// last time do we really need to this?
			app.time = 0
			app.animation_paused = false
			reload_shaders(app)
		} else // we have a new error message, show it
		if err != app.err_msg {
			delete(app.err_msg)
			app.err_msg = err
		} else // same error message, we dont need this one
		{
			delete(err)
		}
	}

	if failure {
		imgui.PushStyleColorImVec4(.Text, [4]f32{255, 0, 0, 255})
		imgui.TextWrapped(app.err_msg)
		imgui.PopStyleColor()
	}
}

animation_settings :: proc(app: ^App_State)
{
	if !imgui.CollapsingHeader("Animation Settings") {
		return
	}

	if app.vsync {
		imgui.BeginDisabled()
	}

	slider_fmt: cstring
	if app.framerate >= MAX_FRAMERATE {
		// *whiirrrrrr*
		// "why is my computer making weird noises?"
		slider_fmt = "Unlimited FPS!"
	} else {
		slider_fmt = "%d FPS"
	}

	imgui.SliderInt("Framerate", &app.framerate, 5, MAX_FRAMERATE, slider_fmt, {.ClampOnInput})

	if app.vsync {
		imgui.EndDisabled()
	}

	if imgui.Checkbox("Enable VSync", &app.vsync) {
		_vsync: i32
		if ok := sdl.GL_GetSwapInterval(&_vsync); ok {
			ok &= sdl.GL_SetSwapInterval(_vsync == 0 ? 1 : 0)
			if !ok {
				log.warn("Failed to change swap interval. Error msg:", sdl.GetError())
				app.vsync = !app.vsync
			}
		}
	}

	imgui.SeparatorEx({.Horizontal}, 2)

	imgui.SliderFloat("Anim. Speed", &app.time_speed, 0.1, 10)
	imgui.Checkbox("Pause Anim.", &app.animation_paused)
	if imgui.Button("Reset Anim.") {
		app.time = 0
		app.animation_paused = false
	}
}

coloring_settings :: proc(app: ^App_State)
{
	if !imgui.CollapsingHeader("Coloring Settings") {
		return
	}

	combo_items: cstring =
		!ODIN_DEBUG ? "HSL Coloring\x00HSLuv Coloring\x00Custom Color Palette\x00Use an Image (doesn't work!)\x00" :
		              "HSL Coloring\x00HSLuv Coloring\x00Custom Color Palette\x00"

	if imgui.Combo(
		"Coloring Method",
		(^i32)(&app.coloring_method),
		combo_items,
	) {
		app.time = 0
		app.animation_paused = false
		reload_shaders(app)
	}

	switch app.coloring_method {
	case .Use_HSL, .Use_HSLuv:
		if imgui.SliderFloat("Saturation", &app.saturation, 0, 100, "%.1f%%") {
			opengl.Uniform1f(app.uniforms.saturation, app.saturation)
		}

		if imgui.SliderFloat("Lightness", &app.lightness, 0, 100, "%.1f%%") {
			opengl.Uniform1f(app.uniforms.lightness, app.lightness)
		}
		
		if imgui.SliderFloat(
			"Gamma Correction",
			&app.gamma_correction,
			-1,
			1,
		) {
			opengl.Uniform1f(app.uniforms.gamma_correction, app.gamma_correction)
		}
	case .Use_Palette:
		rand_color :: proc() -> (color: Color) 
		{
			color.r = rand.float32()
			color.g = rand.float32()
			color.b = rand.float32()
			return
		}

		flags := imgui.ColorEditFlags{.InputRGB, .Uint8}
		colors_changed :=
			imgui.ColorEdit3("A", &app.abcd[0], flags) |
			imgui.ColorEdit3("B", &app.abcd[1], flags) |
			imgui.ColorEdit3("C", &app.abcd[2], flags) |
			imgui.ColorEdit3("D", &app.abcd[3], flags)

		if imgui.Button("Random Palette") {
			app.abcd[0] = rand_color()
			app.abcd[1] = rand_color()
			app.abcd[2] = rand_color()
			app.abcd[3] = rand_color()

			colors_changed = true
		}

		if colors_changed {
			opengl.Uniform3fv(app.uniforms.abcd, 4, ([^]f32)(&app.abcd))
		}
	case .Use_Texture:
		if imgui.Button("Choose Image") {
			sdl.ShowSimpleMessageBox(
				{.ERROR},
				"Doesn't Work",
				"This functionality doesn't work right now, sorry <3",
				app.window,
			)

			/*
			@(static, rodata)
			filters := [?]sdl.DialogFileFilter {
				{"PNG & JPEG images", "png;jpg;jpeg"},
				{"All Files", "*"},
			}

			// not (windows) asan friendly!
			sdl.ShowOpenFileDialog(
				dialog_file_callback,
				app,
				app.window,
				([^]sdl.DialogFileFilter)(&filters),
				len(filters),
				nil,
				false,
			)
			*/
		}

	}
}

// doesn't work </3
dialog_file_callback :: proc "c" (
	userdata: rawptr,
	filelist: [^]cstring,
	filter: i32,
) 
{
	context = runtime.default_context()

	if filelist == nil {
		return
	}

	app := (^App_State)(userdata)

	width, height, channels: i32
	stbi.set_flip_vertically_on_load((i32)(true))
	image_data := stbi.load(filelist[0], &width, &height, &channels, 0)
	defer stbi.image_free(image_data)

	if image_data == nil {
		msg := fmt.ctprintf(
			"Failed to load the image file \"%s\".",
			filelist[0],
		)

		sdl.ShowSimpleMessageBox(
			{.WARNING},
			"Could not load image",
			msg,
			app.window,
		)
		return
	}
	// sdl.GL_MakeCurrent(app.window, app.gl_ctx)
	// opengl.load_up_to(3, 3, sdl.gl_set_proc_address)
	// opengl.BindBuffer(opengl.PIXEL_UNPACK_BUFFER, 0)
	// opengl.BindTexture(opengl.TEXTURE_2D, app.texture)
	opengl.DeleteTextures(1, &app.texture)
	opengl.TexImage2D(
		opengl.TEXTURE_2D,
		0,
		channels == 4 ? opengl.RGBA : opengl.RGB,
		// opengl.RGB,
		width,
		height,
		0,
		channels == 4 ? opengl.RGBA : opengl.RGB,
		// opengl.RGB,
		opengl.UNSIGNED_BYTE,
		image_data,
	)

	opengl.TexParameteri(
		opengl.TEXTURE_2D,
		opengl.TEXTURE_WRAP_S,
		opengl.REPEAT,
	) // set texture wrapping to GL_REPEAT (default wrapping method)
	opengl.TexParameteri(
		opengl.TEXTURE_2D,
		opengl.TEXTURE_WRAP_T,
		opengl.REPEAT,
	)
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
	opengl.GenerateMipmap(opengl.TEXTURE_2D)
}

/*
window_size_in_px :: proc (win: ^sdl.Window) -> (w, h: i32)
{
	sdl.GetWindowSizeInPixels(win, &w, &h)
	return w, h
}

window_size :: proc (win: ^sdl.Window) -> (w, h: i32)
{
	sdl.GetWindowSize(win, &w, &h)
	return w, h
}
*/