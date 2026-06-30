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
import "core:os"

Ui_State :: struct {
	image_data:       Image_Data,
	slice_colors:     [dynamic]Color,
	window:           ^sdl.Window,
	window_icon:      ^sdl.Surface,
	io:               ^imgui.IO,
	math_font:        ^imgui.Font,
	ini_path:         cstring,
	function:         cstring,
	err_msg:          cstring,
	coloring_method:  Coloring_Method,
	time_speed:       f32,
	main_scale:       f32,
	framerate:        i32,
	animation_paused: bool,
	hide_ui:          bool,
	vsync:            bool,
}

Image_Data :: struct {
	filename:     string,
	size:         [2]i32,
	display_size: [2]f32,
	pixels:       rawptr,
	type:         u32,
	is_resident:  bool,
}

Coloring_Method :: enum i32 {
	Use_HSL,
	Use_HSLuv,
	Use_Discrete_Slices,
	Use_Continuous_Slices,
	Use_Palette,
	Use_Image,
}

IMGUI_CONFIG_FLAGS :: imgui.ConfigFlags{.NavEnableKeyboard, .DockingEnable}
APP_ICON_PNG_DATA :: #load("../favicon/favicon-64x64.png", []u8)
MAIN_FONT_DATA :: #load("../fonts/DMSans.ttf", []u8)
MAX_FRAMERATE :: 260
PREFERRED_IMG_SIZE :: 196 // alternatives: 128, 256
INI_FILENAME :: "kolori.ini"

setup_sdl :: proc(app: ^App_State) 
{
	_ = sdl.SetAppMetadata("Kolori", "0.4.0", "io.github.neroist.kolori")
	_ = sdl.SetAppMetadataProperty(
		sdl.PROP_APP_METADATA_CREATOR_STRING,
		"neroist",
	)
	_ = sdl.SetAppMetadataProperty(
		sdl.PROP_APP_METADATA_TYPE_STRING,
		"application",
	)

	if !sdl.Init({.VIDEO}) {
		log.fatal("[sdl.Init] Failed to initialize SDL3. Error msg:", sdl.GetError())

		app.running = false
		return
	}

	// primary_display := sdl.GetPrimaryDisplay()
	// app.main_scale = sdl.GetDisplayContentScale(primary_display)
	// if app.main_scale == 0 {
	// 	app.main_scale = 1
	// }

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
	app.io.IniFilename = nil
	app.io.LogFilename = nil

	when !ODIN_DEBUG {
		app.ini_path = get_ini_path()
		// seems kind of redundant, why not set `app.io.IniFilename` directly?
		// but we get a heap-use-after-free error if we don't do this </3
		app.io.IniFilename = app.ini_path
		app.io.LogFilename = app.log_path
	}

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

/* 
 * read from the `KOLORI_INI_DIRECTORY` environment variable to get where to
 * store the imgui-generated ini file.
 * 
 * if empty, we default to the directory meant for non-essential application
 * data of the user running the program. If we cannot retrieve or create this
 * directory or the user-provided one in the environment variable, we do a
 * final fallback to the current working directory of the process.
 * 
 * if unset, we return nil, implying ui state should not be saved.
 */
get_ini_path :: proc (allocator := context.allocator, loc := #caller_location) -> cstring
{
	ini_dir, found := os.lookup_env("KOLORI_INI_DIRECTORY", context.temp_allocator)
	if !found {
		ini_dir, _ = os.user_state_dir(context.temp_allocator)
	} else if len(ini_dir) == 0 {
		return nil
	}

	if !os.exists(ini_dir) {
		err := os.make_directory(ini_dir)
		if err != nil {
			log.warn("Unable to create ini file directory, falling back to cwd")
			ini_dir = "."
		}
	}

	ini_path_str, _ := os.join_path({ini_dir, INI_FILENAME}, context.temp_allocator)
	return strings.clone_to_cstring(ini_path_str, allocator, loc)
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
	if app.hide_ui {
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
	// default to true, else we get a seg fault as `app.err_msg` is nil
	@(static) ok_input := true

	imgui.PushFontFloat(app.math_font, 22)
	imgui.Text("f(z) =")
	imgui.PopFont()

	// ensure proper spacing between the text "f(z) =" and the following text
	// input
	imgui.SameLine(62.5)

	if imgui.InputText("##function", (app.function), FUNCTION_BUF_SIZE) {
		new_err_msg := validate(app.function)
		ok_input = (new_err_msg == nil)

		if ok_input {
			app.time.val = 0
			app.animation_paused = false
			reload_shaders(app)
		} else if new_err_msg != app.err_msg {
			delete(app.err_msg)
			app.err_msg = new_err_msg
		} else {
			delete(new_err_msg)
		}
	}

	if !ok_input {
		RED :: 0xFF_00_00_FF
		imgui.PushStyleColor(.Text, RED)
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

			// the ImGui checkbox toggles the `app.vsync` boolean when it is
			// clicked
			// 
			// since we have failed to actually to set/unset vsync, we undo
			// the toggling of the boolean here
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
	rand_color :: proc() -> (color: Color) 
	{
		color.r = rand.float32()
		color.g = rand.float32()
		color.b = rand.float32()
		return
	}
	
	center_next_widget :: proc(width: f32)
	{
		avail := imgui.GetContentRegionAvail().x
		off := max((avail - width) / 2, 0)
		imgui.SetCursorPosX(imgui.GetCursorPosX() + off)
	}
	
	centered_button :: proc(label: cstring) -> bool
	{
		frame_padding := imgui.GetStyle().FramePadding.x
		width := imgui.CalcTextSize(label).x + frame_padding + 2
		center_next_widget(width)
		return imgui.Button(label)
	}
	
	num_digits :: proc(#any_int n: int) -> f32
	{
		return math.trunc(math.log10((f32)(n))) + 1
	}

	if !imgui.CollapsingHeader("Coloring Settings", {.DefaultOpen}) {
		return
	}

	combo_labels := [Coloring_Method]cstring{
		.Use_HSL = "HSL Coloring",
		.Use_HSLuv = "HSLuv Coloring",
		.Use_Discrete_Slices = "Pizza Slices",
		.Use_Continuous_Slices = "Pizza Slices",
		.Use_Palette = "Custom Color Palette",
		.Use_Image = "Use an Image",
	}

	// which `Use_*_Slices` item to skip
	//
	// used to help with persisting the coloring method when its one of the
	// *_slices coloring methods
	@static skip := bit_set[Coloring_Method]{.Use_Continuous_Slices}

	if imgui.BeginCombo("##coloring_method_combo", combo_labels[app.coloring_method]) {
		defer imgui.EndCombo()

		for label, method in combo_labels {
			// we don't want the same label to come up twice
			if method in skip {
				continue
			}

			item_is_selected := app.coloring_method == method

			if imgui.Selectable(label, item_is_selected) {
				app.time.val = 0
				app.animation_paused = false
				app.coloring_method = method
				reload_shaders(app)
			}

			if item_is_selected {
				imgui.SetItemDefaultFocus()
			}
		}
	}

	imgui.SeparatorText("Configuration")

	switch app.coloring_method {
	case .Use_HSL, .Use_HSLuv:
		if imgui.SliderFloat("Saturation", &app.saturation.val, 0, 100, "%.1f%%") {
			update_uniform(app.saturation)
		}

		if imgui.SliderFloat("Lightness", &app.lightness.val, 0, 100, "%.1f%%") {
			update_uniform(app.lightness)
		}

		if imgui.SliderFloat("Gamma Correction", &app.gamma_correction.val, -1, 1) {
			update_uniform(app.gamma_correction)
		}
	case .Use_Discrete_Slices, .Use_Continuous_Slices:
		update_slices: bool
		defer if update_slices {
			img_data: Image_Data
			img_data.filename = "slice_colors"
			img_data.size = {(i32)(len(app.slice_colors)), 1}
			img_data.pixels = raw_data(app.slice_colors)
			img_data.type = opengl.FLOAT

			load_texture(app.slices, &img_data)
		}

		if imgui.RadioButtonIntPtr(
			"Discrete",
			(^i32)(&app.coloring_method),
			(i32)(Coloring_Method.Use_Discrete_Slices),
		) {
			app.time.val = 0
			app.animation_paused = false
			skip -= {.Use_Discrete_Slices}
			skip += {.Use_Continuous_Slices}
			reload_shaders(app)
		}
		imgui.SameLine()
		if imgui.RadioButtonIntPtr(
			"Continuous",
			(^i32)(&app.coloring_method),
			(i32)(Coloring_Method.Use_Continuous_Slices)
		) {
			app.time.val = 0
			app.animation_paused = false
			skip -= {.Use_Continuous_Slices}
			skip += {.Use_Discrete_Slices}
			reload_shaders(app)
		}

		imgui.SeparatorText("Slice Colors")

		for &color, idx in app.slice_colors {
			// todo: inelegant
			// note: limits max # of colors to 256
			id: [10]u8
			id[0] = '#'
			id[1] = '#'
			id[2] = (u8)(idx)
			update_slices |= imgui.ColorEdit3(transmute(cstring)(&id), &color, {.Uint8})
			
			id[0] = '-'
			id[1] = '#'
			id[2] = '#'
			id[3] = (u8)(idx)
			imgui.SameLine()
			if imgui.Button(transmute(cstring)(&id)) {
				ordered_remove(&app.slice_colors, idx)
				update_slices = true
			}

			id = {'R','a','n','d','o','m','#','#',(u8)(idx),0}
			imgui.SameLine()
			if imgui.Button(transmute(cstring)(&id)) {
				color = rand_color()
				update_slices = true
			}
		}

		if centered_button("Add Color") {
			if len(app.slice_colors) >= 255 {
				break
			}

			update_slices = true
			append(&app.slice_colors, Color{0.0, 0.0, 0.0})
		}
	case .Use_Palette:
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
			update_uniform(app.abcd)
		}
	case .Use_Image:
		if !app.image_data.is_resident && app.image_data.pixels != nil {
			load_texture(app.image, &app.image_data)
			stbi.image_free(app.image_data.pixels)
		}

		if app.image_data.is_resident {
			// horizontally center image
			imgui.SetCursorPosX((imgui.GetWindowSize().x - app.image_data.display_size.x) * 0.5)

			tex_ref := imgui.TextureRef { _TexID = (imgui.TextureID)(app.image.id) }
			imgui.Image(tex_ref, app.image_data.display_size, {0, 1}, {1, 0})

			// todo: this obviously doesn't work, and its dumb to have even
			// thought of
			text_len := num_digits(app.image_data.size.x) + num_digits(app.image_data.size.y) + 1
			center_next_widget(text_len)
			imgui.Text("%ix%i", app.image_data.size.x, app.image_data.size.y)
		}

		if imgui.Button("Choose Image") {
			// stb image supports JPG, PNG, TGA, BMP, PSD, GIF, HDR, and PIC images
			@(static, rodata)
			filters := [?]sdl.DialogFileFilter {
				{"Image files", "jpg;jpeg;png;tga;bmp;psd;gif;hdr;pic"},
				{"All Files", "*"},
			}

			// multi-threaded on windows, so we can't use opengl functions in
			// the dialog callback
			//
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

		update_tex_params: bool
		defer if update_tex_params {
			set_tex_parameters(app.image)
		}

		imgui.Text("Horizontal Repeat:")
		imgui.SameLine()
		update_tex_params |= imgui.RadioButtonIntPtr(
			"Normal##norm_wrap_s",
			&app.image.wrap_s,
			opengl.REPEAT,
		)
		imgui.SameLine()
		update_tex_params |= imgui.RadioButtonIntPtr(
			"Mirrored##mirr_wrap_s",
			&app.image.wrap_s,
			opengl.MIRRORED_REPEAT,
		)

		imgui.Text("Vertical Repeat:")
		imgui.SameLine()
		update_tex_params |= imgui.RadioButtonIntPtr(
			"Normal##norm_wrap_t",
			&app.image.wrap_t,
			opengl.REPEAT,
		)
		imgui.SameLine()
		update_tex_params |= imgui.RadioButtonIntPtr(
			"Mirrored##mirr_wrap_t",
			&app.image.wrap_t,
			opengl.MIRRORED_REPEAT,
		)

		// rgba swizzle?
		// min filter? mag filter?
	}
}

// used both as a callback for `sdl.ShowOpenFileDialog` and as a regular
// function to load image data into `app.image_data`
load_image :: proc "c" (app_ptr: rawptr, filelist: [^]cstring, filter: i32 = 0) 
{
	if filelist == nil || filelist[0] == nil {
		return
	}

	// for logging
	context = runtime.default_context()

	// we mostly deal with `image_data`, but we need access to the main window
	// to display an error popup if the image failed to load, for whatever
	// reason
	app := (^App_State)(app_ptr) 

	stbi.set_flip_vertically_on_load(1)
	app.image_data.filename = strings.clone_from_cstring(filelist[0])
	app.image_data.pixels = stbi.load(filelist[0], &app.image_data.size.x, &app.image_data.size.y, nil, 3)
	app.image_data.type = opengl.UNSIGNED_BYTE
	app.image_data.is_resident = false

	if app.image_data.pixels != nil {
		// preserve aspect ratio while resizing to preferred size
		app.image_data.display_size = ([2]f32)(app.image_data.size)
		if (app.image_data.size.x >= PREFERRED_IMG_SIZE) ||
		   (app.image_data.size.y >= PREFERRED_IMG_SIZE) {
			// we want to resize by the minimum amount, to avoid distorting
			// the image as much as possible
			longest_side := (f32)(max(app.image_data.size.x, app.image_data.size.y))
			scale_by := PREFERRED_IMG_SIZE / longest_side
			app.image_data.display_size *= scale_by
		}

		log.infof(
			"Loaded %ix%i image at \"%s\" from disk",
			app.image_data.size.x,
			app.image_data.size.y,
			app.image_data.filename
		)
	} else {
		failure_reason := stbi.failure_reason() // not threadsafe?

		log.warnf(
			"Failed to load the image file \"%s\". Reason: \"%s\"",
			filelist[0],
			failure_reason,
		)

		msg := fmt.ctprintf(
			"Failed to load the image file \"%s\".\n\nReason:\"%s\"",
			filelist[0],
			failure_reason,
		)

		sdl.ShowSimpleMessageBox({.WARNING}, "Could not load image", msg, app.window)
	}
}
