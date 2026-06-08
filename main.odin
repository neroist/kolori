#+feature dynamic-literals

package kolori

import "core:c"
import gl "vendor:OpenGL"
import sdl "vendor:sdl3"
import imgui "odin-imgui"
import "imgui/imgui_impl_sdlrenderer3"
import "imgui/imgui_impl_sdl3"
// import "core:fmt"
import "core:log"

// three coloring modes:
//  1. predefined coloring functions for H, S, and L
//  2. user-provided coloring functions (HSL)
//  3. image (texture)
//  4. palette (https://iquilezles.org/articles/palettes/)

App_Context :: struct {
    window: ^sdl.Window,
    renderer: ^sdl.Renderer,
    gl_ctx: sdl.GLContext,
    vao: u32,
    program: u32,
    uniforms: map[string]i32
}

Coloring_Method :: enum u32 {
    Use_Default = 0,
    Use_Palette = 1,
    Use_Texture = 2,
    Use_User    = 3,
}

GL_MAJOR_VERSION :: 3
GL_MINOR_VERSION :: 3

main :: proc ()
{
    context.logger = log.create_console_logger()

    window, renderer, gl_ctx := setup_sdl()
    defer {
        sdl.GL_DestroyContext(gl_ctx)
        sdl.DestroyRenderer(renderer)
        sdl.DestroyWindow(window)
        sdl.Quit()
    }

    // nvg_ctx := nvg_gl.Create({.ANTI_ALIAS, .STENCIL_STROKES, .DEBUG})
    // nvg.CreateFont(nvg_ctx, "normal", "./fonts/CourbeSans.ttf")
    // defer nvg_gl.Destroy(nvg_ctx)

    vao, program, uniforms := setup_gl(window, gl_ctx)
    defer {
        delete(uniforms)
        gl.DeleteProgram(program)
    }

    // mu_ctx, atlas_texture := setup_mu(renderer)
    // defer {
    //     sdl.DestroyTexture(atlas_texture)
    //     free(mu_ctx)
    // }

    zoom: f32 = 1
    zoom_speed: f32 = 1.1
    shift: [2]f32

    render_loop: for {
        // gl.ClearColor(0.3, 0.3, 0.32, 1.0)
		// gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT | gl.STENCIL_BUFFER_BIT)
        gl.UseProgram(program)

        event: sdl.Event
        for sdl.PollEvent(&event) {
            #partial switch event.type {
            case .QUIT:
                break render_loop
            case .WINDOW_RESIZED:
                width, height: i32
                sdl.GetWindowSize(window, &width, &height)
                gl.Viewport(0, 0, width, height)
                gl.Uniform2i(uniforms["resolution"], width, height)
            case .MOUSE_WHEEL:
                if event.wheel.y > 0 {
                    zoom *= zoom_speed 
                } else if event.wheel.y < 0 {
                    zoom /= zoom_speed 
                }

                gl.Uniform1f(uniforms["zoom"], zoom)
            case .MOUSE_MOTION:
                if .LEFT in event.motion.state {
                    width, height: i32
                    sdl.GetWindowSize(window, &width, &height)

                    motion := [2]f32{event.motion.xrel, event.motion.yrel}
                    scale := [2]f32{(f32)(-width), (f32)(height)}
                    shift += (motion / scale) * zoom
                    
                    gl.Uniform2f(uniforms["shift"], shift.x, shift.y)
                }
            }
        }

        render_graph(vao, program)
        // draw_ui(mu_ctx)
        // render_ui(mu_ctx, nvg_ctx, atlas_texture)
        sdl.GL_SwapWindow(window)
    }
}

setup_sdl :: proc () -> (window: ^sdl.Window, renderer: ^sdl.Renderer, gl_ctx: sdl.GLContext)
{
    if !sdl.Init({.VIDEO}) {
        log.error("[sdl.Init]", sdl.GetError())
        sdl.Quit()
    }

    sdl.CreateWindowAndRenderer("Kolori", 800, 600, {.OPENGL, .RESIZABLE}, &window, &renderer)
    if window == nil || renderer == nil {
        log.error("[sdl.CreateWindowAndRenderer]", sdl.GetError())
        sdl.Quit()
    }

    gl_ctx = sdl.GL_CreateContext(window)
    if gl_ctx == nil {
        log.error("[sdl.GL_CreateContext]", sdl.GetError())
        sdl.Quit()
    }

    return window, renderer, gl_ctx
}

setup_gl :: proc (window: ^sdl.Window, gl_ctx: sdl.GLContext) -> (vao, program: u32, uniforms: map[string]i32)
{
    context_flags: sdl.GLContextFlag
    when ODIN_DEBUG { context_flags |= sdl.GL_CONTEXT_DEBUG_FLAG }
    when ODIN_OS == .Darwin { context_flags |= sdl.GL_CONTEXT_FORWARD_COMPATIBLE_FLAG }

    // See odin-lang/Odin issue 2123: https://github.com/odin-lang/odin/issues/2123
    sdl.GL_SetAttribute(.CONTEXT_FLAGS, transmute(i32) (context_flags))
    sdl.GL_SetAttribute(.CONTEXT_PROFILE_MASK, (i32)(sdl.GL_CONTEXT_PROFILE_CORE))
    sdl.GL_SetAttribute(.CONTEXT_MAJOR_VERSION, GL_MAJOR_VERSION)
    sdl.GL_SetAttribute(.CONTEXT_MINOR_VERSION, GL_MINOR_VERSION)
    sdl.GL_SetAttribute(.DOUBLEBUFFER, 1)
    sdl.GL_SetAttribute(.DEPTH_SIZE, 24)
    sdl.GL_SetAttribute(.STENCIL_SIZE, 8)

    sdl.GL_MakeCurrent(window, gl_ctx)

    gl.load_up_to(GL_MAJOR_VERSION, GL_MINOR_VERSION, sdl.gl_set_proc_address)

    width, height: i32
    sdl.GetWindowSize(window, &width, &height)
    gl.Viewport(0, 0, width, height)

    vertices := [?]f32 {
		// Coordinates 
		-1,  1,
		 1,  1,
		-1, -1,
		 1, -1,
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
	vertex_shader := #load("shaders/graph.vert", string)
	fragment_shader := #load("shaders/graph.frag", string)

	program, ok = gl.load_shaders_source(vertex_shader, fragment_shader)

	if !ok {
		log.error("[gl.load_shaders_source]", gl.get_last_error_message())
		sdl.Quit()
	}

    // we dont unbind the program
    // this is to make it easier e.g. to set uniforms
    gl.UseProgram(program)

    uniforms = {
        "zoom" = gl.GetUniformLocation(program, "zoom"),
        "resolution" = gl.GetUniformLocation(program, "resolution"),
        "shift" = gl.GetUniformLocation(program, "shift"),
        "coloring_method" = gl.GetUniformLocation(program, "coloring_method"),
        "texture" = gl.GetUniformLocation(program, "texture"),
    }

	gl.Uniform1i(uniforms["texture"], 0)
    gl.Uniform1f(uniforms["zoom"], 1)
	gl.Uniform2i(uniforms["resolution"], width, height)

    return vao, program, uniforms
}


render_graph :: proc (vao, program: u32)
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
