#version 330 core
precision highp float;
precision highp int;
precision highp sampler2D;

in vec2 pos;
in vec2 tex_coord;
out vec4 FragColor;

uniform float time;
uniform float zoom;
uniform ivec2 resolution;
uniform vec2 shift;
uniform sampler2D tex;
uniform vec3 abcd[4];
uniform float gamma_correction;

const float PI          = 3.14159265358979323846f;
const float TAU         = 6.28318530717958647692f;
const float TWO_OVER_PI = 0.63661977236758134308f;

const vec2 C_I   = vec2(0, 1);
const vec2 C_PI  = vec2(3.14159265358979323846f, 0);
const vec2 C_TAU = vec2(6.28318530717958647692f, 0);
const vec2 C_E   = vec2(2.71828182845904523536f, 0);
const vec2 C_PHI = vec2(1.61803398874989484820f, 0);

float hue2rgb(float f1, float f2, float hue)
{
	if (hue < 0.0)
		hue += 1.0;
	else if (hue > 1.0)
		hue -= 1.0;

	float res;
	if ((6.0 * hue) < 1.0)
		res = f1 + (f2 - f1) * 6.0 * hue;
	else if ((2.0 * hue) < 1.0)
		res = f2;
	else if ((3.0 * hue) < 2.0)
		res = f1 + (f2 - f1) * ((2.0 / 3.0) - hue) * 6.0;
	else
		res = f1;

	return res;
}

vec4 hsl2rgb(vec3 hsl)
{
	vec3 rgb;
	
	if (hsl.y == 0.0) {
		rgb = vec3(hsl.z); // Luminance
	} else {
		float f2;
		
		if (hsl.z < 0.5)
			f2 = hsl.z * (1.0 + hsl.y);
		else
			f2 = hsl.z + hsl.y - hsl.y * hsl.z;
			
		float f1 = 2.0 * hsl.z - f2;
		
		rgb.r = hue2rgb(f1, f2, hsl.x + (1.0/3.0));
		rgb.g = hue2rgb(f1, f2, hsl.x);
		rgb.b = hue2rgb(f1, f2, hsl.x - (1.0/3.0));
	}

	return vec4(rgb, 1);
}

vec4 hsl2rgb(float h, float s, float l)
{
		return hsl2rgb(vec3(h, s, l));
}

/*
HSLUV-GLSL v4.2
HSLUV is a human-friendly alternative to HSL. ( http://www.hsluv.org )
GLSL port by William Malo ( https://github.com/williammalo )
Put this code in your fragment shader.
*/

vec3 hsluv_intersectLineLine(vec3 line1x, vec3 line1y, vec3 line2x, vec3 line2y)
{
		return (line1y - line2y) / (line2x - line1x);
}

vec3 hsluv_distanceFromPole(vec3 pointx,vec3 pointy)
{
		return sqrt(pointx*pointx + pointy*pointy);
}

vec3 hsluv_lengthOfRayUntilIntersect(float theta, vec3 x, vec3 y)
{
		vec3 len = y / (sin(theta) - x * cos(theta));
		if (len.r < 0.0) {len.r=1000.0;}
		if (len.g < 0.0) {len.g=1000.0;}
		if (len.b < 0.0) {len.b=1000.0;}
		return len;
}

float hsluv_maxSafeChromaForL(float L)
{
		mat3 m2 = mat3(
				 3.2409699419045214  ,-0.96924363628087983 , 0.055630079696993609,
				-1.5373831775700935  , 1.8759675015077207  ,-0.20397695888897657 ,
				-0.49861076029300328 , 0.041555057407175613, 1.0569715142428786  
		);
		float sub0 = L + 16.0;
		float sub1 = sub0 * sub0 * sub0 * .000000641;
		float sub2 = sub1 > 0.0088564516790356308 ? sub1 : L / 903.2962962962963;

		vec3 top1   = (284517.0 * m2[0] - 94839.0  * m2[2]) * sub2;
		vec3 bottom = (632260.0 * m2[2] - 126452.0 * m2[1]) * sub2;
		vec3 top2   = (838422.0 * m2[2] + 769860.0 * m2[1] + 731718.0 * m2[0]) * L * sub2;

		vec3 bounds0x = top1 / bottom;
		vec3 bounds0y = top2 / bottom;

		vec3 bounds1x =              top1 / (bottom+126452.0);
		vec3 bounds1y = (top2-769860.0*L) / (bottom+126452.0);

		vec3 xs0 = hsluv_intersectLineLine(bounds0x, bounds0y, -1.0/bounds0x, vec3(0.0) );
		vec3 xs1 = hsluv_intersectLineLine(bounds1x, bounds1y, -1.0/bounds1x, vec3(0.0) );

		vec3 lengths0 = hsluv_distanceFromPole( xs0, bounds0y + xs0 * bounds0x );
		vec3 lengths1 = hsluv_distanceFromPole( xs1, bounds1y + xs1 * bounds1x );

		return  min(lengths0.r,
						min(lengths1.r,
						min(lengths0.g,
						min(lengths1.g,
						min(lengths0.b,
								lengths1.b)))));
}

float hsluv_maxChromaForLH(float L, float H)
{

		float hrad = radians(H);

		mat3 m2 = mat3(
				 3.2409699419045214  ,-0.96924363628087983 , 0.055630079696993609,
				-1.5373831775700935  , 1.8759675015077207  ,-0.20397695888897657 ,
				-0.49861076029300328 , 0.041555057407175613, 1.0569715142428786  
		);
		float sub1 = pow(L + 16.0, 3.0) / 1560896.0;
		float sub2 = sub1 > 0.0088564516790356308 ? sub1 : L / 903.2962962962963;

		vec3 top1   = (284517.0 * m2[0] - 94839.0  * m2[2]) * sub2;
		vec3 bottom = (632260.0 * m2[2] - 126452.0 * m2[1]) * sub2;
		vec3 top2   = (838422.0 * m2[2] + 769860.0 * m2[1] + 731718.0 * m2[0]) * L * sub2;

		vec3 bound0x = top1 / bottom;
		vec3 bound0y = top2 / bottom;

		vec3 bound1x =              top1 / (bottom+126452.0);
		vec3 bound1y = (top2-769860.0*L) / (bottom+126452.0);

		vec3 lengths0 = hsluv_lengthOfRayUntilIntersect(hrad, bound0x, bound0y );
		vec3 lengths1 = hsluv_lengthOfRayUntilIntersect(hrad, bound1x, bound1y );

		return  min(lengths0.r,
						min(lengths1.r,
						min(lengths0.g,
						min(lengths1.g,
						min(lengths0.b,
								lengths1.b)))));
}

float hsluv_fromLinear(float c)
{
		return c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1.0 / 2.4) - 0.055;
}

vec3 hsluv_fromLinear(vec3 c)
{
		return vec3( hsluv_fromLinear(c.r), hsluv_fromLinear(c.g), hsluv_fromLinear(c.b) );
}

float hsluv_toLinear(float c)
{
		return c > 0.04045 ? pow((c + 0.055) / (1.0 + 0.055), 2.4) : c / 12.92;
}

vec3 hsluv_toLinear(vec3 c)
{
		return vec3( hsluv_toLinear(c.r), hsluv_toLinear(c.g), hsluv_toLinear(c.b) );
}

float hsluv_yToL(float Y)
{
		return Y <= 0.0088564516790356308 ? Y * 903.2962962962963 : 116.0 * pow(Y, 1.0 / 3.0) - 16.0;
}

float hsluv_lToY(float L)
{
		return L <= 8.0 ? L / 903.2962962962963 : pow((L + 16.0) / 116.0, 3.0);
}

vec3 xyzToRgb(vec3 tuple)
{
		const mat3 m = mat3( 
				3.2409699419045214  ,-1.5373831775700935 ,-0.49861076029300328 ,
			 -0.96924363628087983 , 1.8759675015077207 , 0.041555057407175613,
				0.055630079696993609,-0.20397695888897657, 1.0569715142428786  );
		
		return hsluv_fromLinear(tuple*m);
}

vec3 rgbToXyz(vec3 tuple)
{
		const mat3 m = mat3(
				0.41239079926595948 , 0.35758433938387796, 0.18048078840183429 ,
				0.21263900587151036 , 0.71516867876775593, 0.072192315360733715,
				0.019330818715591851, 0.11919477979462599, 0.95053215224966058 
		);
		return hsluv_toLinear(tuple) * m;
}

vec3 xyzToLuv(vec3 tuple)
{
		float X = tuple.x;
		float Y = tuple.y;
		float Z = tuple.z;

		float L = hsluv_yToL(Y);
		
		float div = 1./dot(tuple,vec3(1,15,3)); 

		return vec3(
				1.,
				(52. * (X*div) - 2.57179),
				(117.* (Y*div) - 6.08816)
		) * L;
}


vec3 luvToXyz(vec3 tuple) {
		float L = tuple.x;

		float U = tuple.y / (13.0 * L) + 0.19783000664283681;
		float V = tuple.z / (13.0 * L) + 0.468319994938791;

		float Y = hsluv_lToY(L);
		float X = 2.25 * U * Y / V;
		float Z = (3./V - 5.)*Y - (X/3.);

		return vec3(X, Y, Z);
}

vec3 luvToLch(vec3 tuple)
{
		float L = tuple.x;
		float U = tuple.y;
		float V = tuple.z;

		float C = length(tuple.yz);
		float H = degrees(atan(V,U));
		if (H < 0.0) {
				H = 360.0 + H;
		}
		
		return vec3(L, C, H);
}

vec3 lchToLuv(vec3 tuple)
{
		float hrad = radians(tuple.b);
		return vec3(
				tuple.r,
				cos(hrad) * tuple.g,
				sin(hrad) * tuple.g
		);
}

vec3 hsluvToLch(vec3 tuple)
{
		tuple.g *= hsluv_maxChromaForLH(tuple.b, tuple.r) * .01;
		return tuple.bgr;
}

vec3 lchToHsluv(vec3 tuple)
{
		tuple.g /= hsluv_maxChromaForLH(tuple.r, tuple.b) * .01;
		return tuple.bgr;
}

vec3 hpluvToLch(vec3 tuple)
{
		tuple.g *= hsluv_maxSafeChromaForL(tuple.b) * .01;
		return tuple.bgr;
}

vec3 lchToHpluv(vec3 tuple)
{
		tuple.g /= hsluv_maxSafeChromaForL(tuple.r) * .01;
		return tuple.bgr;
}

vec3 lchToRgb(vec3 tuple)
{
		return xyzToRgb(luvToXyz(lchToLuv(tuple)));
}

vec3 rgbToLch(vec3 tuple)
{
		return luvToLch(xyzToLuv(rgbToXyz(tuple)));
}

vec3 hsluvToRgb(vec3 tuple)
{
		return lchToRgb(hsluvToLch(tuple));
}

vec3 rgbToHsluv(vec3 tuple)
{
		return lchToHsluv(rgbToLch(tuple));
}

vec3 hpluvToRgb(vec3 tuple)
{
		return lchToRgb(hpluvToLch(tuple));
}

vec3 rgbToHpluv(vec3 tuple)
{
		return lchToHpluv(rgbToLch(tuple));
}

vec3 luvToRgb(vec3 tuple)
{
		return xyzToRgb(luvToXyz(tuple));
}

// allow vec4's
vec4   xyzToRgb(vec4 c) {return vec4(   xyzToRgb( vec3(c.x,c.y,c.z) ), c.a);}
vec4   rgbToXyz(vec4 c) {return vec4(   rgbToXyz( vec3(c.x,c.y,c.z) ), c.a);}
vec4   xyzToLuv(vec4 c) {return vec4(   xyzToLuv( vec3(c.x,c.y,c.z) ), c.a);}
vec4   luvToXyz(vec4 c) {return vec4(   luvToXyz( vec3(c.x,c.y,c.z) ), c.a);}
vec4   luvToLch(vec4 c) {return vec4(   luvToLch( vec3(c.x,c.y,c.z) ), c.a);}
vec4   lchToLuv(vec4 c) {return vec4(   lchToLuv( vec3(c.x,c.y,c.z) ), c.a);}
vec4 hsluvToLch(vec4 c) {return vec4( hsluvToLch( vec3(c.x,c.y,c.z) ), c.a);}
vec4 lchToHsluv(vec4 c) {return vec4( lchToHsluv( vec3(c.x,c.y,c.z) ), c.a);}
vec4 hpluvToLch(vec4 c) {return vec4( hpluvToLch( vec3(c.x,c.y,c.z) ), c.a);}
vec4 lchToHpluv(vec4 c) {return vec4( lchToHpluv( vec3(c.x,c.y,c.z) ), c.a);}
vec4   lchToRgb(vec4 c) {return vec4(   lchToRgb( vec3(c.x,c.y,c.z) ), c.a);}
vec4   rgbToLch(vec4 c) {return vec4(   rgbToLch( vec3(c.x,c.y,c.z) ), c.a);}
vec4 hsluvToRgb(vec4 c) {return vec4( hsluvToRgb( vec3(c.x,c.y,c.z) ), c.a);}
vec4 rgbToHsluv(vec4 c) {return vec4( rgbToHsluv( vec3(c.x,c.y,c.z) ), c.a);}
vec4 hpluvToRgb(vec4 c) {return vec4( hpluvToRgb( vec3(c.x,c.y,c.z) ), c.a);}
vec4 rgbToHpluv(vec4 c) {return vec4( rgbToHpluv( vec3(c.x,c.y,c.z) ), c.a);}
vec4   luvToRgb(vec4 c) {return vec4(   luvToRgb( vec3(c.x,c.y,c.z) ), c.a);}
// allow 3 floats
vec3   xyzToRgb(float x, float y, float z) {return   xyzToRgb( vec3(x,y,z) );}
vec3   rgbToXyz(float x, float y, float z) {return   rgbToXyz( vec3(x,y,z) );}
vec3   xyzToLuv(float x, float y, float z) {return   xyzToLuv( vec3(x,y,z) );}
vec3   luvToXyz(float x, float y, float z) {return   luvToXyz( vec3(x,y,z) );}
vec3   luvToLch(float x, float y, float z) {return   luvToLch( vec3(x,y,z) );}
vec3   lchToLuv(float x, float y, float z) {return   lchToLuv( vec3(x,y,z) );}
vec3 hsluvToLch(float x, float y, float z) {return hsluvToLch( vec3(x,y,z) );}
vec3 lchToHsluv(float x, float y, float z) {return lchToHsluv( vec3(x,y,z) );}
vec3 hpluvToLch(float x, float y, float z) {return hpluvToLch( vec3(x,y,z) );}
vec3 lchToHpluv(float x, float y, float z) {return lchToHpluv( vec3(x,y,z) );}
vec3   lchToRgb(float x, float y, float z) {return   lchToRgb( vec3(x,y,z) );}
vec3   rgbToLch(float x, float y, float z) {return   rgbToLch( vec3(x,y,z) );}
vec3 hsluvToRgb(float x, float y, float z) {return hsluvToRgb( vec3(x,y,z) );}
vec3 rgbToHsluv(float x, float y, float z) {return rgbToHsluv( vec3(x,y,z) );}
vec3 hpluvToRgb(float x, float y, float z) {return hpluvToRgb( vec3(x,y,z) );}
vec3 rgbToHpluv(float x, float y, float z) {return rgbToHpluv( vec3(x,y,z) );}
vec3   luvToRgb(float x, float y, float z) {return   luvToRgb( vec3(x,y,z) );}
// allow 4 floats
vec4   xyzToRgb(float x, float y, float z, float a) {return   xyzToRgb( vec4(x,y,z,a) );}
vec4   rgbToXyz(float x, float y, float z, float a) {return   rgbToXyz( vec4(x,y,z,a) );}
vec4   xyzToLuv(float x, float y, float z, float a) {return   xyzToLuv( vec4(x,y,z,a) );}
vec4   luvToXyz(float x, float y, float z, float a) {return   luvToXyz( vec4(x,y,z,a) );}
vec4   luvToLch(float x, float y, float z, float a) {return   luvToLch( vec4(x,y,z,a) );}
vec4   lchToLuv(float x, float y, float z, float a) {return   lchToLuv( vec4(x,y,z,a) );}
vec4 hsluvToLch(float x, float y, float z, float a) {return hsluvToLch( vec4(x,y,z,a) );}
vec4 lchToHsluv(float x, float y, float z, float a) {return lchToHsluv( vec4(x,y,z,a) );}
vec4 hpluvToLch(float x, float y, float z, float a) {return hpluvToLch( vec4(x,y,z,a) );}
vec4 lchToHpluv(float x, float y, float z, float a) {return lchToHpluv( vec4(x,y,z,a) );}
vec4   lchToRgb(float x, float y, float z, float a) {return   lchToRgb( vec4(x,y,z,a) );}
vec4   rgbToLch(float x, float y, float z, float a) {return   rgbToLch( vec4(x,y,z,a) );}
vec4 hsluvToRgb(float x, float y, float z, float a) {return hsluvToRgb( vec4(x,y,z,a) );}
vec4 rgbToHslul(float x, float y, float z, float a) {return rgbToHsluv( vec4(x,y,z,a) );}
vec4 hpluvToRgb(float x, float y, float z, float a) {return hpluvToRgb( vec4(x,y,z,a) );}
vec4 rgbToHpluv(float x, float y, float z, float a) {return rgbToHpluv( vec4(x,y,z,a) );}
vec4   luvToRgb(float x, float y, float z, float a) {return   luvToRgb( vec4(x,y,z,a) );}

/*
END HSLUV-GLSL
*/

// based on https://github.com/rust-num/num-complex/blob/master/src/lib.rs
// Copyright 2013 The Rust Project Developers. MIT license
// Ported to GLSL by Andrei Kashcha (github.com/anvaka), available under MIT license as well.
// (+ modifications)

vec2 c_inv(vec2 c) {
	float norm = length(c);
	return vec2(c.x, -c.y) / norm*norm;
}

float arg(vec2 c) {
	return atan(c.y, c.x);
}

// Returns conjugate of a complex number.
vec2 c_conj(vec2 c) {
	return vec2(c.x, -c.y);
}

vec2 c_from_polar(float r, float theta) {
	return vec2(r * cos(theta), r * sin(theta));
}

vec2 c_to_polar(vec2 c) {
	return vec2(length(c), atan(c.y, c.x));
}

// Computes `e^(c)`, where `e` is the base of the natural logarithm.
vec2 c_exp(vec2 c) {
	return c_from_polar(exp(c.x), c.y);
}


// Raises a floating point number to the complex power `c`.
vec2 c_exp(float base, vec2 c) {
	return c_from_polar(pow(base, c.x), c.y * log(base));
}

// Computes the principal value of natural logarithm of `c`.
vec2 c_ln(vec2 c) {
	vec2 polar = c_to_polar(c);
	return vec2(log(polar.x), polar.y);
}

vec2 c_log(vec2 c) {
	return c_ln(c);
}

// Returns the logarithm of `c` with respect to an arbitrary base.
vec2 c_logbase(vec2 c, float base) {
	vec2 polar = c_to_polar(c);
	return vec2(log(polar.r), polar.y) / log(base);
}

// Returns the logarithm of `c` with respect to an arbitrary base.
vec2 c_log2(vec2 c, float base) {
	return c_logbase(c, 2);
}

// Returns the logarithm of `c` with respect to an arbitrary base.
vec2 c_log10(vec2 c, float base) {
	return c_logbase(c, 10);
}

// Computes the square root of complex number `c`.
vec2 c_sqrt(vec2 c) {
	vec2 p = c_to_polar(c);
	return c_from_polar(sqrt(p.x), p.y/2.);
}

// Raises `c` to a floating point power `e`.
vec2 c_pow(vec2 c, float e) {
	vec2 p = c_to_polar(c);
	return c_from_polar(pow(p.x, e), p.y*e);
}

// Raises `c` to a complex power `e`.
vec2 c_pow(vec2 c, vec2 e) {
	vec2 polar = c_to_polar(c);
	return c_from_polar(
		 pow(polar.x, e.x) * exp(-e.y * polar.y),
		 e.x * polar.y + e.y * log(polar.x)
	);
}

// Computes the complex product of `self * other`.
vec2 c_mul(vec2 self, vec2 other) {
		return vec2(self.x * other.x - self.y * other.y, 
					self.x * other.y + self.y * other.x);
}

vec2 c_add(vec2 self, vec2 other) {
		return self + other;
}

vec2 c_sub(vec2 self, vec2 other) {
		return self - other;
}

vec2 c_div(vec2 self, vec2 other) {
		float norm = length(other);
		return vec2(self.x * other.x + self.y * other.y,
					self.y * other.x - self.x * other.y)/(norm * norm);
}

vec2 c_sin(vec2 c) {
	return vec2(sin(c.x) * cosh(c.y), cos(c.x) * sinh(c.y));
}

vec2 c_cos(vec2 c) {
	// formula: cos(a + bi) = cos(a)cosh(b) - i*sin(a)sinh(b)
	return vec2(cos(c.x) * cosh(c.y), -sin(c.x) * sinh(c.y));
}

vec2 c_tan(vec2 c) {
	vec2 c2 = 2. * c;
	return vec2(sin(c2.x), sinh(c2.y))/(cos(c2.x) + cosh(c2.y));
}

vec2 c_csc(vec2 c) {
	return c_inv(c_sin(c));
}

vec2 c_sec(vec2 c) {
	return c_inv(c_cos(c));
}

vec2 c_cot(vec2 c) {
	return c_inv(c_tan(c));
}

vec2 c_atan(vec2 c) {
	// formula: arctan(z) = (ln(1+iz) - ln(1-iz))/(2i)
	vec2 i = C_I;
	vec2 one = vec2(1., 0.);
	vec2 two = one + one;
	if (c == i) {
		return vec2(0., 1./1e-10);
	} else if (c == -i) {
		return vec2(0., -1./1e-10);
	}

	return c_div(
		c_ln(one + c_mul(i, c)) - c_ln(one - c_mul(i, c)),
		c_mul(two, i)
	);
}

vec2 c_asin(vec2 c) {
 // formula: arcsin(z) = -i ln(sqrt(1-z^2) + iz)
	vec2 i = C_I; vec2 one = vec2(1., 0.);
	return c_mul(-i, c_ln(
		c_sqrt(vec2(1., 0.) - c_mul(c, c)) + c_mul(i, c)
	));
}

vec2 c_acos(vec2 c) {
	// formula: arccos(z) = -i ln(i sqrt(1-z^2) + z)
	vec2 i = C_I;

	return c_mul(-i, c_ln(
		c_mul(i, c_sqrt(vec2(1., 0.) - c_mul(c, c))) + c
	));
}

vec2 c_acot(vec2 c) {
	return c_atan(c_inv(c));
}

vec2 c_acsc(vec2 c) {
	return c_asin(c_inv(c));
}

vec2 c_asec(vec2 c) {
	return c_acos(c_inv(c));
}

vec2 c_sinh(vec2 c) {
	return vec2(sinh(c.x) * cos(c.y), cosh(c.x) * sin(c.y));
}

vec2 c_cosh(vec2 c) {
	return vec2(cosh(c.x) * cos(c.y), sinh(c.x) * sin(c.y));
}

vec2 c_tanh(vec2 c) {
	vec2 c2 = 2. * c;
	return vec2(sinh(c2.x), sin(c2.y))/(cosh(c2.x) + cos(c2.y));
}

vec2 c_csch(vec2 c) {
	return c_inv(c_sinh(c));
}

vec2 c_sech(vec2 c) {
	return c_inv(c_cosh(c));
}

vec2 c_coth(vec2 c) {
	return c_inv(c_tanh(c));
}

vec2 c_asinh(vec2 c) {
	// formula: arcsinh(z) = ln(z + sqrt(1+z^2))
	vec2 one = vec2(1., 0.);
	return c_ln(c + c_sqrt(one + c_mul(c, c)));
}

vec2 c_acosh(vec2 c) {
	// formula: arccosh(z) = 2 ln(sqrt((z+1)/2) + sqrt((z-1)/2))
	vec2 one = vec2(1., 0.);
	vec2 two = one + one;
	return c_mul(two,
			c_ln(
				c_sqrt(c_div((c + one), two)) + c_sqrt(c_div((c - one), two))
			));
}

vec2 c_atanh(vec2 c) {
	// formula: arctanh(z) = (ln(1+z) - ln(1-z))/2
	vec2 one = vec2(1., 0.);
	vec2 two = one + one;
	if (c == one) {
		return vec2(1./1e-10, vec2(0.));
	} else if (c == -one) {
		return vec2(-1./1e-10, vec2(0.));
	}
	return c_div(c_ln(one + c) - c_ln(one - c), two);
}


vec2 c_acsch(vec2 c) {
	return c_sinh(c_inv(c));
}

vec2 c_asech(vec2 c) {
	return c_cosh(c_inv(c));
}

vec2 c_acoth(vec2 c) {
	return c_tanh(c_inv(c));
}

// Attempts to identify the gaussian integer whose product with `modulus`
// is closest to `c`
vec2 c_mod(vec2 c, vec2 modulus) {
	vec2 c0 = c_div(c, modulus);
	// This is the gaussian integer corresponding to the true ratio
	// rounded towards zero.
	vec2 c1 = vec2(c0.x - mod(c0.x, 1.), c0.y - mod(c0.y, 1.));
	return c - c_mul(modulus, c1);
}

vec2 c_floor(vec2 c) {
	return floor(c);
}

vec2 c_ceil(vec2 c) {
	return ceil(c);
}

vec2 c_frac(vec2 c) {
	return c - trunc(c);
}

vec2 c_trunc(vec2 c) {
	return trunc(c);
}

vec2 c_gamma(vec2 c) {
	// stirling's approximation
	return c_mul(c_sqrt(c_mul(C_TAU, c)), c_pow(c_div(c, C_E), c));
}

vec2 c_re(vec2 c) {
	return vec2(c.x, 0);
}

vec2 c_real(vec2 c) {
	return vec2(c.x, 0);
}

vec2 c_im(vec2 c) {
	return vec2(c.y, 0);
}

vec2 c_imag(vec2 c) {
	return vec2(c.y, 0);
}

vec2 c_abs(vec2 c) {
	return vec2(length(c), 0);
}

vec2 transform_coordinates(vec4 FragCoord)
{
	vec2 pos = FragCoord.xy;
	float bound = min(resolution.x, resolution.y);

	return zoom * (pos - 0.5f*resolution)/bound + shift;
}

vec4 color_hsl(vec2 z)
{
	// gamma correction
	// const float a = 0.65f;
	float a = gamma_correction;

	float hue = atan(z.y,z.x)/TAU;
	float lightness = TWO_OVER_PI * atan(pow(length(z),a));

	return hsl2rgb(hue, 1.0f, lightness);
}

vec4 color_hsluv(vec2 z)
{
	float a = gamma_correction;
	float hue = degrees(atan(z.y,z.x));
	float lightness = TWO_OVER_PI * atan(pow(length(z),a)) * 33;
	return hsluvToRgb(hue, 100.0f, lightness, 1);
}

vec4 color_texture(vec2 z)
{
	return vec4(texture(tex, z).xyz, 1);
}

// From https://iquilezles.org/articles/palettes/
vec4 color_palette(float t, vec3 a, vec3 b, vec3 c, vec3 d)
{
	return vec4(a + b*cos(TAU * (c*t+d)), 1);
}

vec2 f(vec2 z);
vec2 g(vec2 z);
vec2 h(vec2 z);

void main()
{
	vec2 z = transform_coordinates(gl_FragCoord);

	#if defined(USE_TEXTURE)
		FragColor = color_texture(f(z));
	#elif defined(USE_PALETTE)
		// maybe compose f with a function g:C->R?
		FragColor = color_palette(f(z).x, abcd[0], abcd[1], abcd[2], abcd[3]);
	#elif defined(USE_HSLUV)
		FragColor = color_hsluv(f(z));
	#else
		#define USE_HSL
		FragColor = color_hsl(f(z));
	#endif
}
