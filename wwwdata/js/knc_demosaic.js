/* 
 * GRBG Bayer demosaic (works with RGGB if the image is first flipped
 * horizontally, yielding GRBG).  Uses a simple linear interpolation, with
 * tweaks to improve the appearance of edges.
 *
 * (C)2012 Mike Bourgeous
 */

var KNC = window.KNC || {};

// Hides the given image in the given parent element, adding in its place a
// WebGL canvas that shows a demosaiced version of the image.  If the image is
// reloaded, the new image will be demosaiced automatically.
KNC.initDemosaic = function(img) {
	"use strict";

	var canvas;
	var gl;
	var tex;

	var idxBuf;
	var coordBuf;
	var coordAttr;

	var uniforms = {};

	function initGL() {
		canvas = document.createElement('canvas');
		gl = canvas.getContext('webgl');
		if(gl == null) {
			gl = canvas.getContext('experimental-webgl');
		}
		if(gl == null) {
			throw "No WebGL support.";
		}

		canvas.width = img.offsetWidth;
		canvas.height = img.offsetHeight;
		canvas.style.position = 'absolute';
		canvas.style.margin = '0';
		canvas.style.border = '0';
		canvas.style.padding = '0';
		canvas.style.zIndex = '2';

		gl.disable(gl.BLEND);
		gl.disable(gl.DEPTH_TEST);
		gl.clearColor(0.0, 0.0, 0.0, 1.0);
		gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
	}

	function texLoaded(img) {
		tex.width = img.width;
		tex.height = img.height;
		gl.bindTexture(gl.TEXTURE_2D, tex);
		gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, true);
		gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
		gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
		gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
		gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
		gl.texImage2D(gl.TEXTURE_2D, 0, gl.LUMINANCE, gl.LUMINANCE, gl.UNSIGNED_BYTE, img);
		gl.bindTexture(gl.TEXTURE_2D, null);

		drawScene();
	}

	function initTextures() {
		var imgLoad = img.onload;
		img.onload = function() {
			imgLoad();
			try {
				texLoaded(this);
			} catch(e) {
				console.error("Error updating demosaic image: " + e);
			}
		}

		tex = gl.createTexture();
	}

	var vtxShader =
		"precision highp float;\n" +
		"attribute vec2 aTexCoord;\n" +
		"varying vec2 vTexCoord;\n" +
		"\n" +
		"void main(void) {\n" +
		"	gl_Position = vec4(aTexCoord * 2.0 - 1.0, 1.0, 1.0);\n" +
		"	vTexCoord = aTexCoord;\n" +
		"}";

	var fragShader =
		"precision highp float;\n" +
		"varying vec2 vTexCoord;\n" +
		"uniform sampler2D uSampler;\n" +
		"uniform float pixSizeX;\n" +
		"uniform float pixSizeY;\n" +
		"uniform float texWidth;\n" +
		"uniform float texHeight;\n" +
		"const float cellSize = 2.0;\n" +
		"\n" +
		"vec4 sample(vec2 tc)\n" +
		"{\n" +
		"	return texture2D(uSampler, tc);\n" +
		"}\n" +
		"\n" +
		"vec4 sample(vec2 tc, int xo, int yo)\n" +
		"{\n" +
		"	return texture2D(uSampler, vec2(tc.x + float(xo) * pixSizeX, tc.y - float(yo) * pixSizeY));\n" +
		"}\n" +
		"\n" +
		"// Stores the raw texture coordinate in pixel, whether the pixel is even/odd in offset\n" +
		"void pixelOffset(vec2 tc, out ivec2 pixel, out ivec2 offset)\n" +
		"{\n" +
		"	pixel = ivec2(tc * vec2(texWidth, texHeight));\n" +
		"	offset = ivec2(mod(vec2(pixel), 2.0));\n" +
		"}\n" +
		"\n" +
		"// Returns the average value of the pair with the lowest delta\n" +
		"// (abs(pair1[0] - pair1[1])), or the average of both pairs if the\n" +
		"// deltas are eqaul\n" +
		"float minDelta(vec2 pair1, vec2 pair2)\n" +
		"{\n" +
		"	// Minimum gradient, or bilinear if equal gradients\n" +
		"	float delta = abs(pair1[0] - pair1[1]) - abs(pair2[0] - pair2[1]);\n" +
		"	if(delta == 0.0) {\n" +
		"		return (pair1[0] + pair1[1] + pair2[0] + pair2[1]) * 0.25;\n" +
		"	}\n" +
		"	if(delta < 0.0) {\n" +
		"		return (pair1[0] + pair1[1]) * 0.5;\n" +
		"	}\n" +
		"	return (pair2[0] + pair2[1]) * 0.5;\n" +
		"}\n" +
		"\n" +
		"float red(vec2 tc)\n" +
		"{\n" +
		"	ivec2 pxl, off;\n" +
		"	pixelOffset(tc, pxl, off);\n" +
		"\n" +
		"	vec2 cell = vec2((floor((tc.x * texWidth) / cellSize) * cellSize + 1.5) / texWidth,\n" +
		"			(ceil((tc.y * texHeight) / cellSize) * cellSize - 0.5) / texHeight);\n" +
		"\n" +
		"	if(tc.x <= pixSizeX && off.x == 0) {\n" +
		"		return mix(sample(cell).r, sample(cell, 0, -2).r, float(off.y) / 2.0);\n" +
		"	}\n" +
		"\n" +
		"	if(tc.y <= pixSizeY || off == ivec2(1, 1)) {\n" +
		"		return sample(cell).r;\n" +
		"	}\n" +
		"\n" +
		"	if(off == ivec2(0, 1)) {\n" +
		"		return (sample(cell).r + sample(cell, -2, 0).r) / 2.0;\n" +
		"	}\n" +
		"\n" +
		"	if(off == ivec2(1, 0)) {\n" +
		"		return (sample(cell).r + sample(cell, 0, 2).r) / 2.0;\n" +
		"	}\n" +
		"\n" +
		"	return minDelta(vec2(sample(cell).r, sample(cell, -2, 2).r),\n" +
		"			vec2(sample(cell, -2, 0).r, sample(cell, 0, 2).r));\n" +
		"}\n" +
		"\n" +
		"float green(vec2 tc)\n" +
		"{\n" +
		"	ivec2 pxl, off;\n" +
		"	pixelOffset(tc, pxl, off);\n" +
		"\n" +
		"	if(off == ivec2(0, 1) || off == ivec2(1, 0)) {\n" +
		"		return texture2D(uSampler, tc).r;\n" +
		"	}\n" +
		"\n" +
		"	return minDelta(vec2(sample(tc, -1, 0).r, sample(tc, 1, 0).r),\n" +
		"			vec2(sample(tc, 0, -1).r, sample(tc, 0, 1).r));\n" +
		"}\n" +
		"\n" +
		"float blue(vec2 tc)\n" +
		"{\n" +
		"	ivec2 pxl, off;\n" +
		"	pixelOffset(tc, pxl, off);\n" +
		"\n" +
		"	vec2 cell = vec2((floor((tc.x * texWidth) / cellSize) * cellSize + 0.5) / texWidth,\n" +
		"			(ceil((tc.y * texHeight) / cellSize) * cellSize - 1.5) / texHeight);\n" +
		"\n" +
		"	if(tc.x <= pixSizeX && off.x == 0) {\n" +
		"		return mix(sample(cell).r, sample(cell, 0, -2).r, float(off.y) / 2.0);\n" +
		"	}\n" +
		"\n" +
		"	if(off == ivec2(1, 1)) {\n" +
		"		return sample(cell).r;\n" +
		"	}\n" +
		"\n" +
		"	if(off == ivec2(0, 1)) {\n" +
		"		return (sample(cell).r + sample(cell, -2, 0).r) / 2.0;\n" +
		"	}\n" +
		"\n" +
		"	if(off == ivec2(1, 0)) {\n" +
		"		return (sample(cell).r + sample(cell, 0, 2).r) / 2.0;\n" +
		"	}\n" +
		"\n" +
		"	return minDelta(vec2(sample(cell).r, sample(cell, -2, 2).r),\n" +
		"			vec2(sample(cell, -2, 0).r, sample(cell, 0, 2).r));\n" +
		"}\n" +
		"\n" +
		"vec4 demosaicSample(vec2 tc)\n" +
		"{\n" +
		"	vec2 cell = vec2((floor((tc.x * texWidth) / cellSize) * cellSize + 0.5) / texWidth,\n" +
		"			(ceil((tc.y * texHeight) / cellSize) * cellSize - 0.5) / texHeight);\n" +
		"	vec2 offset = tc - cell;\n" +
		"\n" +
		"	return vec4(red(tc), green(tc), blue(tc), 1.0);\n" +
		"}\n" +
		"\n" +
		"void main(void) {\n" +
		"	vec4 tex = vec4(0.0);\n" +
		"	tex = demosaicSample(vTexCoord);\n" +
		"	gl_FragColor = tex;\n" +
		"}";

	function initShaders() {
		var vtx = gl.createShader(gl.VERTEX_SHADER);
		gl.shaderSource(vtx, vtxShader);
		gl.compileShader(vtx);
		if(!gl.getShaderParameter(vtx, gl.COMPILE_STATUS)) {
			console.error("Error compiling vertex shader: " + gl.getShaderInfoLog(vtx));
			throw "Error compiling vertex shader.";
		}

		var frag = gl.createShader(gl.FRAGMENT_SHADER);
		gl.shaderSource(frag, fragShader);
		gl.compileShader(frag);
		if(!gl.getShaderParameter(frag, gl.COMPILE_STATUS)) {
			console.error("Error compiling fragment shader: " + gl.getShaderInfoLog(frag));
			throw "Error compiling fragment shader.";
		}

		var program = gl.createProgram();
		gl.attachShader(program, vtx);
		gl.attachShader(program, frag);
		gl.linkProgram(program);
		if(!gl.getProgramParameter(program, gl.LINK_STATUS)) {
			console.error("Error linking shader program: " + gl.getProgramInfoLog(program));
			throw "Error linking shader program.";
		}
		gl.useProgram(program);

		coordAttr = gl.getAttribLocation(program, "aTexCoord");
		gl.enableVertexAttribArray(coordAttr);

		uniforms.uSampler = gl.getUniformLocation(program, "uSampler");
		uniforms.pixSizeX = gl.getUniformLocation(program, "pixSizeX");
		uniforms.pixSizeY = gl.getUniformLocation(program, "pixSizeY");
		uniforms.texWidth = gl.getUniformLocation(program, "texWidth");
		uniforms.texHeight = gl.getUniformLocation(program, "texHeight");
	}

	function initBuffers() {
		var idx = [0, 1, 2, 0, 2, 3];
		idxBuf = gl.createBuffer();
		gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, idxBuf);
		gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, new Uint16Array(idx), gl.STATIC_DRAW);

		var coord = [
			0.0, 0.0,
			1.0, 0.0,
			1.0, 1.0,
			0.0, 1.0,
			];
		coordBuf = gl.createBuffer();
		gl.bindBuffer(gl.ARRAY_BUFFER, coordBuf);
		gl.bufferData(gl.ARRAY_BUFFER, new Float32Array(coord), gl.STATIC_DRAW);
	}

	function drawScene() {
		gl.viewport(0, 0, canvas.width, canvas.height);

		gl.activeTexture(gl.TEXTURE0);
		gl.bindTexture(gl.TEXTURE_2D, tex);
		gl.uniform1i(uniforms.uSampler, 0);

		gl.uniform1f(uniforms.pixSizeX, 1.0 / tex.width);
		gl.uniform1f(uniforms.pixSizeY, 1.0 / tex.height);
		gl.uniform1f(uniforms.texWidth, tex.width);
		gl.uniform1f(uniforms.texHeight, tex.height);

		gl.bindBuffer(gl.ARRAY_BUFFER, coordBuf);
		gl.vertexAttribPointer(coordAttr, 2, gl.FLOAT, false, 0, 0);

		gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, idxBuf);
		gl.drawElements(gl.TRIANGLES, 6, gl.UNSIGNED_SHORT, 0);
	}

	try {
		initGL();
		img.parentNode.appendChild(canvas);
		img.style.visibility = 'hidden';

		initTextures();
		initShaders();
		initBuffers();

	} catch(e) {
		console.error("Error enabling WebGL-based demosaic: " + e);

		img.style.visibility = 'inherit';
		if(canvas != null) {
			canvas.style.visibility = 'hidden';
		}

		throw e;
	}
};
