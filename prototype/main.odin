// An elementary program in Odin which creates a rainbow RGB triangle
// which rotates over time.
//
// Created by Benjamin Thompson. Available at:
// https://github.com/bg-thompson/OpenGL-Tutorials-In-Odin
// Last updated: 2024.09.15
//
// To compile and run the program with optimizations, use the command
//
//     odin run Rainbow-Triangle -o:speed
//
// Created for educational purposes. Used verbatim, it is probably
// unsuitable for production code.

package vivi

import "base:runtime"
import "core:fmt"
import "core:math"
import "core:os"
import "core:time"
import gl "vendor:OpenGL"
import "vendor:glfw"
import "vendor:stb/image"

// Create alias types for vertex array / buffer objects
VAO :: u32
VBO :: u32
ShaderProgram :: u32

// Global variables.
global_vao: VAO
global_shader: ShaderProgram
watch: time.Stopwatch
dilation: f32 = 1

main :: proc() {
	// Setup window, including priming for OpenGL 3.3.
	glfw.Init()
	defer glfw.Terminate()

	glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, 3)
	glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, 3)
	glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)

	window := glfw.CreateWindow(800, 800, "Rainbow Triangle", nil, nil)
	assert(window != nil)
	defer glfw.DestroyWindow(window)

	glfw.MakeContextCurrent(window)
	// glfw.SwapInterval(1)

	// Load OpenGL 3.3 function pointers.
	gl.load_up_to(3, 3, glfw.gl_set_proc_address)

	w, h := glfw.GetFramebufferSize(window)
	gl.Viewport(0, 0, w, h)

	// Key press / Window-resize behaviour
	glfw.SetKeyCallback(window, callback_key)
	glfw.SetScrollCallback(window, callback_scroll)
	glfw.SetWindowRefreshCallback(window, window_refresh)

	// Create equilateral triangle on unit circle.
	vertices := [?]f32 {
		// Coordinates ; Colors ; Texture
		-1,  1,    1, 0, 0,    0, 1,
		 1,  1,    0, 1, 0,    1, 1,
		-1, -1,    1, 1, 0,    0, 0,
		 1, -1,    0, 0, 1,    1, 0,
		
		// 1, -1, 0, 0, 1,
		// -1,  1, 1, 0, 0,
	}

	
	// Set up vertex array / buffer objects.
	gl.GenVertexArrays(1, &global_vao)
	gl.BindVertexArray(global_vao)
	
	width, height, num_chanels: i32
	image.set_flip_vertically_on_load((i32)(true))
	image_data := image.load("image.jpg", &width, &height, &num_chanels, 0)
	fmt.println("image data?", image_data[0] != 0)
	
	texture: u32
	gl.GenTextures(1, &texture)
	gl.BindTexture(gl.TEXTURE_2D, texture)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.REPEAT);	// set texture wrapping to GL_REPEAT (default wrapping method)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.REPEAT);
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR);
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
	gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGB, width, height, 0, gl.RGB, gl.UNSIGNED_BYTE, image_data)
	gl.GenerateMipmap(gl.TEXTURE_2D)
	image.image_free(image_data)

	vbo: VBO
	gl.GenBuffers(1, &vbo)
	gl.BindBuffer(gl.ARRAY_BUFFER, vbo)

	// Describe GPU buffer.
	gl.BufferData(
		gl.ARRAY_BUFFER, // target
		size_of(vertices), // size of the buffer object's data store
		&vertices, // data used for initialization
		gl.STATIC_DRAW,
	) // usage

	// Position and color attributes. Don't forget to enable!
	gl.VertexAttribPointer(
		0, // index
		2, // size
		gl.FLOAT, // type
		gl.FALSE, // normalized
		7 * size_of(f32), // stride
		0,
	) // offset

	gl.VertexAttribPointer(1, 3, gl.FLOAT, gl.FALSE, 7 * size_of(f32), 2 * size_of(f32))
	gl.VertexAttribPointer(2, 2, gl.FLOAT, gl.FALSE, 7 * size_of(f32), 5 * size_of(f32))

	// Enable the vertex position and color attributes defined above.
	gl.EnableVertexAttribArray(0)
	gl.EnableVertexAttribArray(1)
	gl.EnableVertexAttribArray(2)

	// Compile vertex shader and fragment shader.
	// Note how much easier this is in Odin than in C++!

	program_ok: bool
	vertex_shader := (string)(#load("vertex.vert"))
	fragment_shader := (string)(#load("fragment.frag"))

	global_shader, program_ok = gl.load_shaders_source(vertex_shader, fragment_shader)

	if !program_ok {
		fmt.println("ERROR: Failed to load and compile shaders.")
		os.exit(1)
	}

	gl.UseProgram(global_shader)
	gl.Uniform1i(gl.GetUniformLocation(global_shader, "tex"), 0)

	// Start rotation timer.
	// time.stopwatch_start(&watch)

	for !glfw.WindowShouldClose(window) {
		glfw.PollEvents()
		// If a key press happens, .PollEvents calls callback_key, defined below.
		// Note: glfw.PollEvents blocks on window menu interaction selection or
		// window resize. During window_resize, glfw.SetWindowRefreshCallback
		// calls window_refresh to redraw the window.

		render_screen(window, global_vao)
	}
}

render_screen :: proc "contextless" (window: glfw.WindowHandle, vao: VAO) {
	// Send theta rotation value to GPU.
	// raw_duration := time.stopwatch_duration(watch)
	// secs := f32(time.duration_seconds(raw_duration))
	theta := -(f32)(glfw.GetTime())
	gl.Uniform1f(gl.GetUniformLocation(global_shader, "theta"), theta)
	gl.Uniform1f(gl.GetUniformLocation(global_shader, "dilation"), dilation)

	// gl.BindVertexArray(vao)
	// defer gl.BindVertexArray(0)

	// Draw commands.
	gl.ClearColor(0.1, 0.1, 0.1, 1)
	gl.Clear(gl.COLOR_BUFFER_BIT)

	gl.DrawArrays(
		gl.TRIANGLE_STRIP, // Draw triangles.
		0, // Begin drawing at index 0.
		4,
	) // Use 3 indices.
	glfw.SwapBuffers(window)
}

// Quit the window if the ESC key is pressed. This procedure is called by
// glfw.SetKeyCallback.
callback_key :: proc "c" (window: glfw.WindowHandle, key, scancode, action, mods: i32) {
	if action == glfw.PRESS && key == glfw.KEY_ESCAPE {
		glfw.SetWindowShouldClose(window, true)
	}
}

callback_scroll :: proc "c" (window: glfw.WindowHandle, xoffset, yoffset: f64) {
	sgn :: proc "c" (x: f64) -> f32 {
		if x > 0 do return 1
		if x < 0 do return -1
		return 0
	}
	// fun :: proc "c" (x: f64) -> f64 { return 1/x if x < 0 else x}
	dilation += 0.01 * sgn(-yoffset)
	dilation = max(0.01, dilation)
	// dilation += (f32)(fun(yoffset))
}

// If the window needs to be redrawn (e.g. the user resizes the window), redraw the window.
// This procedure is called by  glfw.SetWindowRefreshCallback.
window_refresh :: proc "c" (window: glfw.WindowHandle) {
	gl.Viewport(0, 0, glfw.GetWindowSize(window))
	render_screen(window, global_vao)
}
