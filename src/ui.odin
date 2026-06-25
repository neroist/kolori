package kolori

import "../odin-imgui/imgui_impl_opengl3"
import "../odin-imgui/imgui_impl_sdl3"
import stbi "vendor:stb/image"
import opengl "vendor:OpenGL"
import imgui "../odin-imgui"
import sdl "vendor:sdl3"
import "core:math/rand"
import "core:strings"
import "base:runtime"
import "core:math"
import "core:fmt"
import "core:log"

Ui_State :: struct {
	img:              Image_Data,
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

Image_Data :: struct {
	filename:     string,
	size:         [2]i32,
	display_size: [2]f32,
	pixels:       [^]u8,
	size_str:     cstring,
	is_resident:  bool,
}

Coloring_Method :: enum i32 {
	Use_HSL,
	Use_HSLuv,
	Use_Palette,
	Use_Image,
}

IMGUI_CONFIG_FLAGS :: imgui.ConfigFlags{.NavEnableKeyboard, .DockingEnable}
APP_ICON_PNG_DATA :: #load("../favicon/favicon-64x64.png", []u8)
MAIN_FONT_DATA :: #load("../fonts/DMSans.ttf", []u8)
MAX_FRAMERATE :: 260
PREFERRED_IMG_SIZE :: 196 // alternatives: 128, 256
UI_CONFIG_FILE :: #config(UI_CONFIG_FILE, "kolori.ini")

setup_sdl :: proc(app: ^App_State) 
{
	_ = sdl.SetAppMetadata("Kolori", "0.2.0", "com.neroist.kolori")
	_ = sdl.SetAppMetadataProperty(
		sdl.PROP_APP_METADATA_URL_STRING,
		"https://github.com/neroist/kolori",
	)

	if !sdl.Init({.VIDEO}) {
		log.fatal("[sdl.Init] Failed to initialize SDL3. Error msg:", sdl.GetError())

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
		log.fatal("[sdl.CreateWindow] Failed to create window. Error msg:", sdl.GetError())

		app.running = false
		return
	}

	discard: i32
	app.window_icon = sdl.CreateSurfaceFrom(64, 64, .RGB24, nil, 3*64)
	app.window_icon.pixels = stbi.load_from_memory(
		raw_data(APP_ICON_PNG_DATA),
		(i32)(len(APP_ICON_PNG_DATA)),
		&discard, // we get a seg fault if these are set to nil
		&discard,
		&discard,
		3,
	)

	sdl.SetWindowPosition(app.window, sdl.WINDOWPOS_CENTERED, sdl.WINDOWPOS_CENTERED)
	sdl.ShowWindow(app.window)
}

setup_imgui :: proc(app: ^App_State) 
{
	imgui.CreateContext()
	imgui_impl_opengl3.Init("#version 300 es")
	imgui_impl_sdl3.InitForOpenGL(app.window, app.gl.ctx)

	app.io = imgui.GetIO()
	app.io.ConfigFlags += IMGUI_CONFIG_FLAGS
	app.io.IniFilename = UI_CONFIG_FILE

	style_imgui() // app.main_scale

	// these are simply the defaults as described in `imgui.odin`
	font_cfg := imgui.FontConfig {
		FontDataOwnedByAtlas = false,
		ExtraSizeScale       = 1,
		GlyphMaxAdvanceX     = math.F32_MAX,
		RasterizerMultiply   = 1,
		RasterizerDensity    = 1,
	}

	// this will also be used as the main ui font,
	// as it is the first font loaded
	app.math_font = imgui.FontAtlas_AddFontFromMemoryTTF(
		app.io.Fonts,
		raw_data(MAIN_FONT_DATA),
		(i32)(len(MAIN_FONT_DATA)),
		18,
		&font_cfg,
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

	imgui.SameLine(62.5)

	if imgui.InputText("##function", app.function, FUNCTION_BUF_SIZE) {
		err: cstring
		err, failure = validate(app.function).?

		if !failure {
			// if the function hasn't changed since 
			// last time do we really need to do this?
			app.time.val = 0
			app.animation_paused = false
			reload_shaders(app)
		} else if err != app.err_msg {
			delete(app.err_msg)
			app.err_msg = err
		} else {
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
		ok := sdl.GL_GetSwapInterval(&_vsync)
		if ok {
			ok &= sdl.GL_SetSwapInterval(_vsync == 0 ? 1 : 0)
		} 
		
		if !ok {
			log.warnf("Failed to change swap interval. Error msg: \"%s\"", sdl.GetError())
			app.vsync = !app.vsync
		}
	}

	imgui.SeparatorEx({.Horizontal}, 2)

	imgui.SliderFloat("Anim. Speed", &app.time_speed, 0.1, 10)
	imgui.Checkbox("Pause Anim.", &app.animation_paused)
	if imgui.Button("Reset Anim.") {
		app.time.val = 0
		app.animation_paused = false
	}
}

coloring_settings :: proc(app: ^App_State) 
{
	if !imgui.CollapsingHeader("Coloring Settings", {.DefaultOpen}) {
		return
	}

	combo_items: cstring = "HSL Coloring\x00HSLuv Coloring\x00Custom Color Palette\x00Use an Image\x00"

	if imgui.Combo("Coloring Method", (^i32)(&app.coloring_method), combo_items) {
		app.time.val = 0
		app.animation_paused = false
		reload_shaders(app)
	}

	imgui.SeparatorText("Configuration")

	switch app.coloring_method {
	case .Use_HSL, .Use_HSLuv:
		if imgui.SliderFloat("Saturation", &app.saturation.val, 0, 100, "%.1f%%") {
			// opengl.Uniform1f(app.saturation, app.saturation)
			update_uniform(app.saturation)
		}

		if imgui.SliderFloat("Lightness", &app.lightness.val, 0, 100, "%.1f%%") {
			// opengl.Uniform1f(app.lightness, app.lightness)
			update_uniform(app.lightness)
		}

		if imgui.SliderFloat("Gamma Correction", &app.gamma_correction.val, -1, 1) {
			// opengl.Uniform1f(app.gamma_correction, app.gamma_correction)
			update_uniform(app.gamma_correction)
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
			imgui.ColorEdit3("A", &app.abcd.val[0], flags) |
			imgui.ColorEdit3("B", &app.abcd.val[1], flags) |
			imgui.ColorEdit3("C", &app.abcd.val[2], flags) |
			imgui.ColorEdit3("D", &app.abcd.val[3], flags)

		if imgui.Button("Random Palette") {
			app.abcd.val[0] = rand_color()
			app.abcd.val[1] = rand_color()
			app.abcd.val[2] = rand_color()
			app.abcd.val[3] = rand_color()

			colors_changed = true
		}

		if colors_changed {
			// opengl.Uniform3fv(app.uniforms.abcd, 4, ([^]f32)(&app.abcd))
			update_uniform(app.abcd)
		}
	case .Use_Image:
		if !app.img.is_resident && app.img.pixels != nil {
			load_texture(app, &app.img)
			stbi.image_free(app.img.pixels)
		}

		if app.img.is_resident {
			// horizontally center image
			imgui.SetCursorPosX((imgui.GetWindowSize().x - app.img.display_size.x) * 0.5)

			tex_ref := imgui.TextureRef {
				_TexID = (imgui.TextureID)(app.texture.id),
			}
			imgui.Image(tex_ref, app.img.display_size, {0, 1}, {1, 0})

			imgui.PushStyleVarImVec2(.SelectableTextAlign, {0.5, 0.5})
			imgui.Selectable(app.img.size_str)
			imgui.PopStyleVar()
		}

		if imgui.Button("Choose Image") {
			// stb image supports JPG, PNG, TGA, BMP, PSD, GIF, HDR, and PIC images
			@(static, rodata)
			filters := [?]sdl.DialogFileFilter {
				{"Image files", "jpg;jpeg;png;tga;bmp;psd;gif;hdr;pic"},
				{"All Files", "*"},
			}

			// multi-threaded on windows, so we can't use opengl functions in
			// the dialog callback.
			// also not asan friendly on windows
			sdl.ShowOpenFileDialog(
				load_image,
				app,
				app.window,
				([^]sdl.DialogFileFilter)(&filters),
				len(filters),
				nil,
				false,
			)
		}

		imgui.SeparatorText("Image Settings")

		upd_tex_params: bool
		defer if upd_tex_params {
			set_tex_parameters(app.texture.wrap_s, app.texture.wrap_t)
		}

		imgui.Text("Horizontal Repeat:")
		imgui.SameLine()
		upd_tex_params |= imgui.RadioButtonIntPtr(
			"Normal##norm_wrap_s",
			&app.texture.wrap_s,
			opengl.REPEAT,
		)
		imgui.SameLine()
		upd_tex_params |= imgui.RadioButtonIntPtr(
			"Mirrored##mirr_wrap_s",
			&app.texture.wrap_s,
			opengl.MIRRORED_REPEAT,
		)

		imgui.Text("Vertical Repeat:")
		imgui.SameLine()
		upd_tex_params |= imgui.RadioButtonIntPtr(
			"Normal##norm_wrap_t",
			&app.texture.wrap_t,
			opengl.REPEAT,
		)
		imgui.SameLine()
		upd_tex_params |= imgui.RadioButtonIntPtr(
			"Mirrored##mirr_wrap_t",
			&app.texture.wrap_t,
			opengl.MIRRORED_REPEAT,
		)

		// rgba swizzle?
		// min filter? mag filter?
	}
}

load_image :: proc "c" (app_ptr: rawptr, filelist: [^]cstring, filter: i32 = 0) 
{
	if filelist == nil || filelist[0] == nil {
		return
	}

	context = runtime.default_context()
	app := (^App_State)(app_ptr)

	stbi.set_flip_vertically_on_load(1)
	app.img.filename = strings.clone_from_cstring(filelist[0])
	app.img.pixels = stbi.load(filelist[0], &app.img.size.x, &app.img.size.y, nil, 3)
	app.img.is_resident = false

	if app.img.pixels != nil {
		delete(app.img.size_str)
		app.img.size_str = fmt.caprintf("%ix%i", app.img.size.x, app.img.size.y)

		// preserve aspect ratio while resizing to preferred size
		app.img.display_size = ([2]f32)(app.img.size)
		if (app.img.size.x >= PREFERRED_IMG_SIZE) || (app.img.size.y >= PREFERRED_IMG_SIZE) {
			scale_by := PREFERRED_IMG_SIZE / (f32)(max(app.img.size.x, app.img.size.y))
			app.img.display_size *= scale_by
		}

		log.infof("Loaded %s image at \"%s\" from disk", app.img.size_str, app.img.filename)
	} else {
		msg := fmt.ctprintf(
			"Failed to load the image file \"%s\".\n\nReason:\"%s\"",
			filelist[0],
			stbi.failure_reason(), // not threadsafe?
		)

		sdl.ShowSimpleMessageBox({.WARNING}, "Could not load image", msg, app.window)
	}
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
