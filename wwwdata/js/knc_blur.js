/* GPU selective smoothing - (C)2012 Mike Bourgeous */

var KNC = window.KNC || {};

// gl - A WebGL context from a canvas tag.
// w - The width of the images to be processed.
// h - The height of the images to be processed.
//
// Returns a function that accepts one required parameter: the object to get
// image data from (an Image, or an img, canvas, or video tag).  An optional
// second boolean parameter toggles smoothing, which defaults to true.  The
// function returns the texture object that holds the smoothed image (modify it
// at your peril).  This texture will be overwritten each time the function is
// called.
//
// The returned function object will have .width and .height properties, and a
// .cleanup() function that will delete the associated WebGL buffers and
// textures.
//
// FIXME: will only work correctly at 640x480
// TODO: Check for GL errors
// TODO: Use a single framebuffer for all texture sizes and just resize it?
KNC.initBlur = function(gl, w, h) {
	var texType = gl.FLOAT;
	if(gl.getExtension('OES_texture_float') == null) {
		if(console) {
			console.log("OES_texture_float is not supported.  It's going to get bumpy.");
		}
		texType = gl.UNSIGNED_BYTE;
	}

	/**************** Initialize framebuffers ****************/
	function createFB(w, h) {
		var fb = gl.createFramebuffer();
		gl.bindFramebuffer(gl.FRAMEBUFFER, fb);
		fb.width = w;
		fb.height = h;

		fb.tex = gl.createTexture();
		fb.tex.width = w;
		fb.tex.height = h;
		gl.bindTexture(gl.TEXTURE_2D, fb.tex);
		gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
		gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
		gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
		gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
		gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, fb.width, fb.height, 0, gl.RGBA, texType, null);

		var rbuf = gl.createRenderbuffer();
		gl.bindRenderbuffer(gl.RENDERBUFFER, rbuf);
		gl.renderbufferStorage(gl.RENDERBUFFER, gl.DEPTH_COMPONENT16, fb.width, fb.height);

		gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, fb.tex, 0);
		gl.framebufferRenderbuffer(gl.FRAMEBUFFER, gl.DEPTH_ATTACHMENT, gl.RENDERBUFFER, rbuf);

		gl.bindTexture(gl.TEXTURE_2D, null);
		gl.bindRenderbuffer(gl.RENDERBUFFER, null);
		gl.bindFramebuffer(gl.FRAMEBUFFER, null);

		return fb;
	}

	var fb1 = createFB(h, w); // Framebuffer for first linear blur
	var fb2 = createFB(w, h); // Framebuffer for second linear blur


	/**************** Initialize geometry buffers ****************/
	// Vertex buffer for normal orientation
	var aspect = w / h;
	var z = -Math.sqrt(3);
	var vtx = [
		-aspect, -1.0, z,
		aspect, -1.0, z,
		aspect, 1.0, z,
		-aspect, 1.0, z,
		];
	var vtxBuf = gl.createBuffer();
	vtxBuf = gl.createBuffer();
	gl.bindBuffer(gl.ARRAY_BUFFER, vtxBuf);
	gl.bufferData(gl.ARRAY_BUFFER, new Float32Array(vtx), gl.STATIC_DRAW);

	// Vertex buffer for rotated orientation
	var vtx90 = [
		1/aspect, -1.0, z,
		1/aspect, 1.0, z,
		-1/aspect, 1.0, z,
		-1/aspect, -1.0, z,
		];
	var vtx90Buf = gl.createBuffer();
	gl.bindBuffer(gl.ARRAY_BUFFER, vtx90Buf);
	gl.bufferData(gl.ARRAY_BUFFER, new Float32Array(vtx90), gl.STATIC_DRAW);

	// Texture coordinate buffer for normal orientation
	var tc = [
		0.0, 0.0,
		1.0, 0.0,
		1.0, 1.0,
		0.0, 1.0,
		];
	var tcBuf = gl.createBuffer();
	gl.bindBuffer(gl.ARRAY_BUFFER, tcBuf);
	gl.bufferData(gl.ARRAY_BUFFER, new Float32Array(tc), gl.STATIC_DRAW);

	// Texture coordinate buffer for rotated orientation
	var tc90 = [
		1.0, 0.0,
		1.0, 1.0,
		0.0, 1.0,
		0.0, 0.0,
		];
	var tc90Buf = gl.createBuffer();
	gl.bindBuffer(gl.ARRAY_BUFFER, tc90Buf);
	gl.bufferData(gl.ARRAY_BUFFER, new Float32Array(tc90), gl.STATIC_DRAW);

	// Vertex index buffer for drawing triangles
	var idx = [0, 1, 2, 0, 2, 3];
	var idxCount = idx.length;
	var idxBuf = gl.createBuffer();
	gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, idxBuf);
	gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, new Uint16Array(idx), gl.STATIC_DRAW);


	/**************** Initialize shaders ****************/
	function getShader(isVertex, sourceText) {
		var shader = gl.createShader(isVertex ? gl.VERTEX_SHADER : gl.FRAGMENT_SHADER);
		gl.shaderSource(shader, sourceText);
		gl.compileShader(shader);
		if(!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
			throw "Error while compiling " + (isVertex ? "vertex" : "fragment") +
				" shader: " + gl.getShaderInfoLog(shader);
		}
		return shader;
	}

	var blurProgram = gl.createProgram();

	// Vertex shader
	var vtxText =
		"precision highp float;\n" +
		"attribute vec3 aVtxPos;\n" +
		"attribute vec2 aTexCoord;\n" +
		"\n" +
		"uniform mat4 uMatrix;\n" +
		"\n" +
		"varying vec2 vTexCoord;\n" +
		"\n" +
		"void main(void) {\n" +
		"	gl_Position = uMatrix * vec4(aVtxPos, 1.0);\n" +
		"	vTexCoord = aTexCoord;\n" +
		"}";
	blurProgram.vtxShader = getShader(true, vtxText);

	// Fragment shader
	// TODO: Calculate IR field shadows cast by each point, avoid using
	// points that cast the shadow for hole filling (i.e. shadows fall on
	// more distant objects; don't use close objects to fill shadows)?
	var fragText = // TODO: Find some cleaner way of including this source
		"precision highp float;\n" +
		"\n" +
		"varying vec2 vTexCoord;\n" +
		"\n" +
		"uniform sampler2D uSampler;\n" +
		"\n" +
		"uniform float pixSize;\n" +
		"uniform lowp int blur;\n" +
		"uniform float kernel[11];\n" +
		"\n" +
		"vec4 sample(vec2 tc, int offset)\n" +
		"{\n" +
		"	return texture2D(uSampler, vec2(tc.x - float(offset) * pixSize, tc.y));\n" +
		"}\n" +
		"\n" +
		"float kernVal(int index)\n" +
		"{\n" +
		"	/* GLSL doesn't permit variable array offsets. */\n" +
		"	if(index == 0) {\n" +
		"		return kernel[0];\n" +
		"	} else if(index == 1) {\n" +
		"		return kernel[1];\n" +
		"	} else if(index == 2) {\n" +
		"		return kernel[2];\n" +
		"	} else if(index == 3) {\n" +
		"		return kernel[3];\n" +
		"	} else if(index == 4) {\n" +
		"		return kernel[4];\n" +
		"	} else if(index == 5) {\n" +
		"		return kernel[5];\n" +
		"	} else if(index == 6) {\n" +
		"		return kernel[6];\n" +
		"	} else if(index == 7) {\n" +
		"		return kernel[7];\n" +
		"	} else if(index == 8) {\n" +
		"		return kernel[8];\n" +
		"	} else if(index == 9) {\n" +
		"		return kernel[9];\n" +
		"	} else if(index == 10) {\n" +
		"		return kernel[10];\n" +
		"	}\n" +
		"	return 0.0;\n" +
		"}\n" +
		"\n" +
		"vec4 blurSample(vec2 tc)\n" +
		"{\n" +
		"	float limitUp;\n" +
		"	float limitDn;\n" +
		"	#define RANGE(d) (limitDn < (d) && (d) < limitUp)\n" +
		"\n" +
		"	vec4 sum = vec4(0.0);\n" +
		"	vec4 base = sample(tc, 0);\n" +
		"	vec4 s;\n" +
		"	float total = 0.0000001;\n" +
		"	float kv, d;\n" +
		"\n" +
		"	if(base.r == 0.0) {\n" +
		"		return vec4(0.0, 0.0, 0.0, 1.0);\n" +
		"	}\n" +
		"\n" +
		"	limitDn = -mix(9.0 / 256.0, 2.0 / 256.0, base.r);\n" +
		"	limitUp = mix(15.0 / 256.0, 3.0 / 256.0, base.r);\n" +
		"\n" +
		"	for(int i = -10; i < 0; i++) {\n" +
		"		kv = kernVal(i + 10);\n" +
		"		s = sample(tc, i);\n" +
		"		d = s.r - base.r;\n" +
		"		if(s.r != 0.0 && RANGE(d)) {\n" +
		"			total += kv;\n" +
		"			sum += s * kv;\n" +
		"		}\n" +
		"	}\n" +
		"	for(int i = 0; i <= 10; i++) {\n" +
		"		kv = kernVal(10 - i);\n" +
		"		s = sample(tc, i);\n" +
		"		d = s.r - base.r;\n" +
		"		if(s.r != 0.0 && RANGE(d)) {\n" +
		"			total += kv;\n" +
		"			sum += s * kv;\n" +
		"		}\n" +
		"	}\n" +
		"\n" +
		"	sum /= total;\n" +
		"\n" +
		"	if(RANGE(sum.r - base.r)) {\n" +
		"		return sum;\n" +
		"	} else {\n" +
		"		return base;\n" +
		"	}\n" +
		"}\n" +
		"\n" +
		"void main(void) {\n" +
		"	vec4 tex;\n" +
		"	if(blur == 1) {\n" +
		"		tex = blurSample(vTexCoord);\n" +
		"	} else if(blur == 0) {\n" +
		"		tex = texture2D(uSampler, vTexCoord);\n" +
		"	} else if(blur <= -1) {\n" +
		"		tex = 16.0 * (texture2D(uSampler, vTexCoord) + 0.025 * float(blur));\n" +
		"	}\n" +
		"	gl_FragColor = tex;\n" +
		"}\n";
	blurProgram.fragShader = getShader(false, fragText);

	// Link program
	gl.attachShader(blurProgram, blurProgram.vtxShader);
	gl.attachShader(blurProgram, blurProgram.fragShader);
	gl.linkProgram(blurProgram);
	if(!gl.getProgramParameter(blurProgram, gl.LINK_STATUS)) {
		throw "An error occurred while linking the blur shader program: " +
			gl.getProgramInfoLog(blurProgram);
	}
	gl.useProgram(blurProgram);

	// Attributes
	blurProgram.aVtxPos = gl.getAttribLocation(blurProgram, "aVtxPos");
	gl.enableVertexAttribArray(blurProgram.aVtxPos);

	blurProgram.aTexCoord = gl.getAttribLocation(blurProgram, "aTexCoord");
	gl.enableVertexAttribArray(blurProgram.aTexCoord);

	// Uniforms
	blurProgram.uMatrix = gl.getUniformLocation(blurProgram, "uMatrix");
	blurProgram.uSampler = gl.getUniformLocation(blurProgram, "uSampler");
	blurProgram.uPixSize = gl.getUniformLocation(blurProgram, "pixSize");
	blurProgram.uBlur = gl.getUniformLocation(blurProgram, "blur");

	gl.uniform1fv(
			gl.getUniformLocation(blurProgram, "kernel"),
			new Float32Array([
				0.015720524,
				0.0227074236,
				0.0301310044,
				0.0377001456,
				0.0452692868,
				0.0522561863,
				0.0586608443,
				0.0639010189,
				0.0678311499,
				0.0703056769,
				0.0710334789,
				])
			);


	/**************** Actual image processing ****************/
	// Stores the given image data in the given texture.  If tex is null, a
	// new texture will be created.
	var tex = gl.createTexture();
	function getTexForImage(img) {
		gl.bindTexture(gl.TEXTURE_2D, tex);
		gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, true); // FIXME: Is this a global setting?
		gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, img);

		gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
		gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
		gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
		gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);

		gl.bindTexture(gl.TEXTURE_2D, null);

		tex.width = img.width || 640;
		tex.height = img.height || 480;

		return tex;
	}

	function drawScene(fb, tex, vtxBuf, tcBuf, blur) {
		gl.bindFramebuffer(gl.FRAMEBUFFER, fb);

		gl.enable(gl.BLEND);
		gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);
		gl.disable(gl.DEPTH_TEST);
		gl.clearColor(0.0, 0.0, 0.0, 0.0); // fully transparent
		gl.clear(gl.COLOR_BUFFER_BIT);

		gl.viewport(0, 0, fb.width, fb.height);
		gl.useProgram(blurProgram);

		var perspMatrix = makePerspective(60, fb.width / fb.height, 0.1, 10.0);
		gl.uniformMatrix4fv(blurProgram.uMatrix, false, new Float32Array(perspMatrix.flatten()));

		gl.bindBuffer(gl.ARRAY_BUFFER, vtxBuf);
		gl.vertexAttribPointer(blurProgram.aVtxPos, 3, gl.FLOAT, false, 0, 0);

		gl.bindBuffer(gl.ARRAY_BUFFER, tcBuf);
		gl.vertexAttribPointer(blurProgram.aTexCoord, 2, gl.FLOAT, false, 0, 0);

		gl.activeTexture(gl.TEXTURE0);
		gl.bindTexture(gl.TEXTURE_2D, tex);
		gl.uniform1i(blurProgram.uSampler, 0);

		gl.uniform1f(blurProgram.uPixSize, 1.0 / tex.width);

		gl.uniform1i(blurProgram.uBlur, blur);

		gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, idxBuf);
		gl.drawElements(gl.TRIANGLES, idxCount, gl.UNSIGNED_SHORT, 0);

		gl.bindFramebuffer(gl.FRAMEBUFFER, null);
	}

	// The image processing function returned to the caller
	var texFunc = function(img, blur) {
		blur = blur == null ? true : blur;

		// Load image data into texture
		tex = getTexForImage(img);

		// Fill/blur image
		drawScene(fb1, tex, vtx90Buf, tcBuf, blur ? 1 : 0);
		drawScene(fb2, fb1.tex, vtxBuf, tc90Buf, blur ? 1 : 0);

		return fb2.tex;
	}

	texFunc.width = w;
	texFunc.height = h;
	texFunc.cleanup = function() {
		//gl.deleteTexture...  TODO
	}

	return texFunc;
}
