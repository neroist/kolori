## What is this?
Kolori ("to color" in Esperanto) is an application that allows you to create
beautiful images from mathematical functions. 

An important note--users with epilepsy are not recommended to use the
animation feature (using "t" in your function input) with high speed values or
otherwise rapidly-changing functions. Zooming out too far during an animation
is also recommended. This advice is very general and depends heavily on the
function being graphed. Still stay cautious, however.

### Gallery
See the `gallery/` directory for a gallery of generated images.

## How to use?

### Controls
- Use your mouse cursor/WASD/arrow keys to pan. If you are on a touchscreen
device you may also simply use your finger.
- Scroll, `+`/`-`, or `z`/`x` to zoom in/out.
- `h` to hide/show all UI. Hold `Shift` to also hide/show your cursor.
- `r` to reload shaders. Hold `Shift` to also reset zoom and pan.
- `p` to pause/unpause animations. Animations will also unpause when switching
functions.
- `f` or `F11` to toggle fullscreen.
- `F12` to take a screenshot. It will be saved in the curent woking directory
with filename `kolori_screenshotDD-MM-YYYY_HHMMSS.png`.
- `ESC` to reset zoom and pan. Hold `Shift` to also reset animations (set time to
zero). Hold `Ctrl` to only perform the latter.

You may always hold `Shift` to zoom/pan faster.

### Function input
Input a valid mathematical expression into the "Function" input box using the
complex variable "z" and/or the scalar time variable "t". Only the "+", "-", 
"*", "/", "%", and "^" operators are allowed. Implicit multiplication is
also supported. A list of supported functions is found at the top of
`src/translator.odin`. You may also use the constants "i", "pi", "tau", "e",
and "phi" (the Golden Ratio).

## Features?
Some features, such as zooming, panning, and function input are evident both
in existance, usage, and ability. This section discusses some of the more
interesting features.

### Animations
Use the scalar variable "t" (stands for "time") in your function for
animations. "t" increases linearly with time elapsed.
> Example: "z * e^(t*i)" to rotate the plane.

You may control how fast "t" increases using the "Speed" slider in the
"Settings" window. The speed has units of "units per second"--a speed of 1
means that "t" will inrease by 1 every second. While the slider is clamped to
0.1..10.0, you may input arbitrary values if you ctrl+click on the slider.
> Example: With a speed of 1, the earlier example will rotate the plane at a
rate of 1 radian per second.

Since, with high speeds or rapidly-changing functions, this may lead to the
display of rapidly flashing lights, using this feature with such is not
recommended for those with epilepsy. Even with perhaps "low" speed values, for
some functions zooming out far may also cause flashing lights to appear.

### Coloring modes
We offer several different coloring modes for coloring the complex plane:

- HSL coloring: This is the default. The hue of a pixel at a point z is 
determined by the z's phase, and lightness determined by the function
L(z) = 2/pi * atan(|r|^a), where "a" is a gamma correction constant by default
set to 0.65. You are given an option to alter the gamma correction constant in
the UI. In the future, you will be able to alter these functions to e.g.
produce contour lines of phase/modulus.

- HSLuv coloring: HSLuv is a perceptually uniform alternative to HSL, where
colors with similar lightness appear similarly bright to the human eye, unlike
HSL or HSV. How we determine pixel hue and lightness is the same as HSL. You
are again allowed to change gamma correction constant. However, we decrease
the lightness by 67% so colors aren't too bright, and turn white too quickly.

- Custom palette generation: Input four colors to generate a palette that
colors the complex plane. Note that, for this coloring mode, only the real
part of the complex function you put in is evaluated. Pixel colors are 
determined using Inigo Quilez’s cosine-based formula for procedural palette
generation. See his article: <https://iquilezles.org/articles/palettes/>.

- Image tiling: Tile the complex plane with an image of your choice. Instead
of a conventional domain coloring based on HSL, phase, and modulus, the plane 
is instead colored based on a tiling of a user-input image. This option 
currently does not work.

## How to build?

### Prerequisites
- This project is made in the **Odin** programming language. As such, you will
need to install the Odin compiler to build. Instructions for installation are
held here: <https://odin-lang.org/docs/install/>.

- For Mac OS, we also use *Clang* to build the ImGui binaries, and *Python* to
run the build commands.

- Finally, on Linux and Mac OS, install **SDL3** and **libc++** using your
system's package manager (`apt`, `pacman`, `brew`, etc.). On Windows,
binaries are already provided.

### Steps
1. Clone the repo.
```sh
$ git clone --recursive https://github.com/neroist/kolori.git
$ cd kolori
```

2. (Mac OS only) Build ImGui.
```sh
$ cd odin-imgui
$ python3 build.py
$ cd ..
```

This step only needs to be done once.

> You may also change the default compiler from `clang` to another compiler if
> need be. We leave such modifications to you. However, in the case that you
> need to compile with `gcc` instead of `clang`, it is sufficient to do a simple
> search-and-replace operation on `build.py` in its entirety.

3. Build the project.
```sh
$ make
```

On Windows without MSYS or MinGW installed, run `build.bat` instead:
```sh
> build.bat
```
