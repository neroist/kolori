#+feature using-stmt

package kolori

import "core:fmt"
import "base:runtime"
import "odin-imgui/imgui_impl_opengl3"
// import sdl_image "vendor:sdl3/image"
import "vendor:stb/image"
import "odin-imgui/imgui_impl_sdl3"
import imgui "odin-imgui"
import gl "vendor:OpenGL"
import sdl "vendor:sdl3"
import "core:log"
import "core:io"

IMGUI_CONFIG_FLAGS :: imgui.ConfigFlags{
    .NavEnableKeyboard,
    .DockingEnable
}

// @(deferred_none=deinit_imgui)
setup_imgui :: proc(app: ^App_Context) 
{
	imgui.CHECKVERSION()
	imgui.CreateContext()

    imgui_impl_sdl3.InitForOpenGL(app.window, app.gl_ctx)
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

draw_ui :: proc(using app: ^App_Context) 
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
	// imgui.ShowUserGuide()
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
			if imgui.SliderFloat("Gamma Correction", &gamma_correction, 0, 1, flags={.ClampOnInput}) {
				gl.Uniform1f(uniforms.gamma_correction, gamma_correction)
			}
        case .Use_Texture:
            if imgui.Button("Choose Image") {
                @(static, rodata)
                filters := [?]sdl.DialogFileFilter{
                    { "PNG & JPEG images",  "png;jpg;jpeg" },
                    { "All Files",  "*" },
                }

                // not asan friendly!
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
    
    app := (^App_Context)(userdata)

    // image := sdl_image.Load(filelist[0])
    // defer sdl.DestroySurface(image)
    // if image == nil {
    //     return
    // }
    width, height, channels: i32
	image.set_flip_vertically_on_load((i32)(true))
	image_data := image.load(filelist[0], &width, &height, &channels, 0)
    // defer image.image_free(image_data)

    if image_data == nil {
        fmt.println("fail!")
        return
    }
    sdl.GL_MakeCurrent(app.window, app.gl_ctx)
    gl.load_up_to(3, 3, sdl.gl_set_proc_address)
    gl.load_up_to(3, 3, sdl.gl_set_proc_address)
    gl.load_up_to(3, 3, sdl.gl_set_proc_address)
    gl.load_up_to(3, 3, sdl.gl_set_proc_address)
    gl.BindBuffer(gl.PIXEL_UNPACK_BUFFER, 0)
    gl.BindTexture(gl.TEXTURE_2D, app.texture)
    gl.TexImage2D(
        gl.TEXTURE_2D,
        0,
        channels == 4 ? gl.RGBA : gl.RGB,
        // gl.RGB,
        width,
        height,
        0,
        channels == 4 ? gl.RGBA : gl.RGB,
        // gl.RGB,
        gl.UNSIGNED_BYTE,
        image_data
    )
    // gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.REPEAT);	// set texture wrapping to GL_REPEAT (default wrapping method)
    // gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.REPEAT);
    // gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR);
    // gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
	// gl.GenerateMipmap(gl.TEXTURE_2D)
}