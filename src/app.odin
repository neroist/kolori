package kolori

import "../odin-imgui/imgui_impl_opengl3"
import "../odin-imgui/imgui_impl_sdl3"
import stbi "vendor:stb/image"
import opengl "vendor:OpenGL"
import imgui "../odin-imgui"
import sdl "vendor:sdl3"
import "base:runtime"
import "core:strings"
import "core:log"
import "core:fmt"
import "core:mem"
import "core:os"

App_State :: struct {
	using gl: GL_State,
	using ui: Ui_State,
	log_path: cstring, // cstring for compat w/ ImGui
	running:  bool,
}

FUNCTION_BUF_SIZE :: 1024
LOG_FILENAME :: "kolori.log"

main :: proc() 
{
	is_file_logger: bool
	context.logger, is_file_logger = get_logger((string)(get_log_path(context.temp_allocator)))
	defer if is_file_logger {
		log.destroy_file_logger(context.logger)
	} else {
		log.destroy_console_logger(context.logger)
	}

	// Lets all love Odin.
	when ODIN_DEBUG {
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		context.allocator = logging_allocator(&track)

		defer {
			if len(track.allocation_map) > 0 {
				fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
				for _, entry in track.allocation_map {
					fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
				}
			}
			mem.tracking_allocator_destroy(&track)
		}
	}

	app: App_State
	setup_app(&app)
	defer {
		delete(app.function)
		delete(app.log_path)
		delete(app.err_msg)
	}

	setup_sdl(&app)
	defer {
		stbi.image_free(app.window_icon.pixels)
		sdl.DestroySurface(app.window_icon)
		sdl.GL_DestroyContext(app.gl.ctx)
		sdl.DestroyWindow(app.window)
		sdl.Quit()
	}

	setup_gl(&app)
	defer {
		opengl.DeleteShader(app.vertex_shader_id)
		opengl.DeleteProgram(app.program)
	}

	setup_imgui(&app)
	defer {
		imgui_impl_opengl3.Shutdown()
		imgui_impl_sdl3.Shutdown()
		imgui.DestroyContext()
		delete(app.slice_colors)
		delete(app.ini_path)
	}

	delta_time: u64
	for app.running {
		frame_begin := sdl.GetTicks()
		defer delta_time = sdl.GetTicks() - frame_begin

		// enforce desired framerate at end of render loop
		defer if !app.vsync || app.framerate <= MAX_FRAMERATE {
			enforce_framerate(delta_time, app.framerate)
		}

		//
		process_events(&app)

		// draw everything to window
		render_graph(&app)
		draw_ui(&app)
		sdl.GL_SwapWindow(app.window)

		// advance time for animations
		if !app.animation_paused {
			advance_time(&app, delta_time)
		}

		// 
		free_all(context.temp_allocator)
	}
}

setup_app :: proc(app: ^App_State) 
{
	app.running = true

	// default settings
	app.zoom.val = 1
	app.gamma_correction.val = 0.65
	app.saturation.val = 100
	app.lightness.val = 100
	app.time_speed = 1
	app.log_path = get_log_path()

	// if we can, we try to enable vsync automatically
	// otherwise, we operate off of 60 fps
	app.framerate = 60

	// set default function, f(z) = z
	buf := make([^]u8, FUNCTION_BUF_SIZE)
	buf[0] = 'z'
	app.function = (cstring)(buf)
}

get_logger :: proc (log_path: string) -> (logger: log.Logger, is_file_logger: bool)
{
	when ODIN_DEBUG {
		logger = log.create_console_logger()
	} else {
		log_file, err := os.open(log_path, {.Create, .Read, .Write, .Trunc})
		if err != nil {
			log.errorf("Failed to open log file. Reason: \"%s\"", os.error_string(err))
			logger = log.create_console_logger() // log to console as fallback
		} else {
			logger = log.create_file_logger(log_file)
			is_file_logger = true
		}
	}
	
	logger.lowest_level = ODIN_DEBUG ? .Debug : .Info
	logger.options -= {.Date}

	return 
}

get_log_path :: proc (allocator := context.allocator, loc := #caller_location) -> cstring
{
	log_dir, err := os.user_log_dir(context.temp_allocator)
	if err != nil {
		log.warnf(
			"Failed to get application log file directory. Probably will fall back to cwd. Error msg: \"%s\"",
			os.error_string(err)
		)

		log_dir = "."
	}

	if !os.exists(log_dir) {
		err := os.make_directory(log_dir)
		if err != nil {
			log.warn("Unable to create log file directory, falling back to cwd")
		}
	}

	log_path_str, _ := os.join_path({log_dir, LOG_FILENAME}, context.temp_allocator)
	return strings.clone_to_cstring(log_path_str, allocator, loc)
}

enforce_framerate :: proc(delta: u64, framerate: i32) 
{
	desired_delta := (u64)(1000 / framerate)

	if desired_delta > delta {
		sdl.Delay((u32)(desired_delta - delta))
	}
}

advance_time :: proc(app: ^App_State, delta: u64) 
{
	delta_secs := (f32)(delta) * 1e-3
	app.time.val += delta_secs * app.time_speed

	update_uniform(app.time)
}
