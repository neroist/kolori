## `dist/`
This folder contains the resources and code needed to create
installers/distributable builds of the program. To create such, run `make dist`
in the root directory of the project. See the
[Building Distributables](#building-distributables) section for more details.  

* `windows/` contains the source code for the Inno Setup installer. The
installer script depends on the `SDL3.dll` file being in the top level
directory.

* `linux/` contains the resources used to build the AppImage distributable for
the application. These resources may also be reused to create `.deb` or
`.flatpak` files, hence the name "linux" rather than "AppImage".

## Building Distributables

### Installer for Windows

For Windows, ensure that you either have `iscc`, the Inno Setup Script
console-mode compiler available in your `PATH`, or use the
`make dist ISCC=...` syntax to point the makefile to where it is on your
system. The `iscc` executable is most commonly found at the location
`C:\Program Files (x86)\Inno Setup 6\iscc.exe`, or similar. 

### AppImage for Linux

We use [linuxdeploy][] to generate and setup the `AppDir` directory, then
[appimagetool][] to create the AppImage file from the generated `AppDir`. If
these tools are already in your `PATH` simply run `make dist`. If not, point
the makefile to where the executables are via the
`make dist LINUXDEPLOY=... APPIMAGETOOL=...` syntax.

<!--
    we add these links at the end rather than inlining them for the benefit
    of those reading this file as text rather than on a webpage
-->
[linuxdeploy]: https://github.com/linuxdeploy/linuxdeploy
[appimagetool]: https://github.com/AppImage/appimagetool