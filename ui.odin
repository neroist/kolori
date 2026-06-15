#+feature using-stmt

package kolori

import "odin-imgui/imgui_impl_opengl3"
import "odin-imgui/imgui_impl_sdl3"
import opengl "vendor:OpenGL"
import "vendor:stb/image"
import imgui "odin-imgui"
import sdl "vendor:sdl3"
import "base:runtime"
import "core:fmt"
import "core:log"

IMGUI_CONFIG_FLAGS :: imgui.ConfigFlags{
    .NavEnableKeyboard,
    .DockingEnable
}

Ui_State :: struct {
	io:               ^imgui.IO,
	math_font:        ^imgui.Font,
	function:         cstring,
	err_msg:          cstring,
	coloring_method:  Coloring_Method,
	time_speed:       f32,
	animation_paused: bool,
	show_ui:          bool,
	vsync:            bool,
}

Coloring_Method :: enum i32 {
	Use_Default,
	Use_Texture,
	Use_Palette,
	// Use_User,
}

// @(deferred_none=deinit_imgui)
setup_imgui :: proc(app: ^App_State) 
{
	imgui.CHECKVERSION()
	imgui.CreateContext()

    imgui_impl_sdl3.InitForOpenGL(app.window, app.gl.ctx)
	imgui_impl_opengl3.Init("#version 330 core")

	app.io = imgui.GetIO()
	app.io.ConfigFlags += IMGUI_CONFIG_FLAGS

    style_imgui()
    
	imgui.FontAtlas_AddFontFromFileTTF(app.io.Fonts, "DMSans.ttf", 18)
	app.math_font = imgui.FontAtlas_AddFontFromFileTTF(app.io.Fonts, "DMSans.ttf", 18)
}

deinit_imgui :: proc()
{
    imgui_impl_opengl3.Shutdown()
    imgui_impl_sdl3.Shutdown()
    imgui.DestroyContext()
}

style_imgui :: proc()
{
    style := imgui.GetStyle()
    
	imgui.StyleColorsDark(style)
	style.WindowRounding = 8
	style.ChildRounding = 8
	style.PopupRounding = 6
	style.FrameRounding = 6
	style.ScrollbarRounding = 6
	style.GrabRounding = 6
	style.TabRounding = 6
}

draw_ui :: proc(using app: ^App_State) 
{
	if !show_ui {
		return
	}

    @(static)
    failure: bool

	imgui_impl_opengl3.NewFrame()
	imgui_impl_sdl3.NewFrame()
	imgui.NewFrame()

	// imgui.ShowDemoWindow()
	imgui.ShowUserGuide()
    // imgui.ShowMetricsWindow()

	imgui.SetNextWindowBgAlpha(0.35)

	imgui.Begin("Plotter", flags = {.AlwaysAutoResize})

	imgui.PushFontFloat(math_font, 22.5)
	imgui.Text("f(z) =")
	imgui.PopFont()

	imgui.SameLine()

	if imgui.InputText("##function", function, 1024) && len(function) > 0 {
        err: cstring
        err, failure = validate(function).?

        // simply `err != err_msg` compiles
        // when `err` is nil and `err_msg` is a string.
        // what does that even do?
        if !failure {
            // if the function hasn't changed since 
            // last time do we really need to this?
            time = 0
			animation_paused = false
			reload_shaders(app)
        } // we have a new error message, show it
        else if err != err_msg {
            delete(err_msg)
            err_msg = err
        } // same error message, we dont need this one
        else {
            delete(err)
        }
	}

    if failure {
        imgui.PushStyleColorImVec4(.Text, [4]f32{255, 0, 0, 255})
        imgui.TextWrapped(err_msg)
        imgui.PopStyleColor()
    }

    if imgui.CollapsingHeader("General Settings") {
        if imgui.Checkbox("Enable VSync", &vsync) {
            _vsync: i32
            ok := sdl.GL_GetSwapInterval(&_vsync)
            ok &= sdl.GL_SetSwapInterval(_vsync == 0 ? 1 : 0)
            if !ok {
                vsync = !vsync
            }
        }
    }

	if imgui.CollapsingHeader("Animation Settings") {
		imgui.SliderFloat("Anim. Speed", &time_speed, 0.1, 10)
		imgui.Checkbox("Pause Anim.", &animation_paused)
		if imgui.Button("Reset Anim.") {
			time = 0
			animation_paused = false
		}
	}

	if imgui.CollapsingHeader("Coloring Settings", {.DefaultOpen}) {
        combo_items: cstring = 
            "Default Method\x00Use an Image\x00Custom Color Palette\x00"
		
		imgui.Combo("Coloring Method", (^i32)(&coloring_method), combo_items)
		
		#partial switch coloring_method {
		case .Use_Default:
			// checkbox instead?
			if imgui.SliderFloat("Gamma Correction", &gamma_correction, -1, 1) {
				opengl.Uniform1f(uniforms.gamma_correction, gamma_correction)
			}
        case .Use_Texture:
            if imgui.Button("Choose Image") {
                @(static, rodata)
                filters := [?]sdl.DialogFileFilter{
                    { "PNG & JPEG images",  "png;jpg;jpeg" },
                    { "All Files",  "*" },
                }

                // not (windows) asan friendly!
                sdl.ShowOpenFileDialog(
                    dialog_file_callback,
                    app,
                    app.window,
                    ([^]sdl.DialogFileFilter)(&filters),
                    len(filters),
                    nil,
                    false
                )
            }

		}
	}
	imgui.End()
    
	imgui.Render()
	imgui_impl_opengl3.RenderDrawData(imgui.GetDrawData())
}

dialog_file_callback :: proc "c" (userdata: rawptr, filelist: [^]cstring, filter: i32)
{
    context = runtime.default_context()
    // fmt.println("hi")
    if filelist == nil {
        return
    }
    
    app := (^App_State)(userdata)

    // image := sdl_image.Load(filelist[0])
    // defer sdl.DestroySurface(image)
    // if image == nil {
    //     return
    // }
    width, height, channels: i32
	image.set_flip_vertically_on_load((i32)(true))
	image_data := image.load(filelist[0], &width, &height, &channels, 0)
    defer image.image_free(image_data)

    if image_data == nil {
        fmt.println("fail!")
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
        image_data
    )

    opengl.TexParameteri(opengl.TEXTURE_2D, opengl.TEXTURE_WRAP_S, opengl.REPEAT);	// set texture wrapping to GL_REPEAT (default wrapping method)
    opengl.TexParameteri(opengl.TEXTURE_2D, opengl.TEXTURE_WRAP_T, opengl.REPEAT);
    opengl.TexParameteri(opengl.TEXTURE_2D, opengl.TEXTURE_MIN_FILTER, opengl.LINEAR_MIPMAP_LINEAR);
    opengl.TexParameteri(opengl.TEXTURE_2D, opengl.TEXTURE_MAG_FILTER, opengl.LINEAR);
	opengl.GenerateMipmap(opengl.TEXTURE_2D)
}