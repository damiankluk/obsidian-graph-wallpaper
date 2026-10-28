#version 440
layout(location = 0) in vec4 qt_Vertex;
layout(location = 1) in vec2 qt_MultiTexCoord0;
layout(location = 0) out vec2 texCoord;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 canvasSize;
    float motionClock;
    float rasterMotionClock;
    float elapsedTime;
    float thoughtLevel;
    float agentLevel;
    float pointerYaw;
    float pointerPitch;
    float rasterPointerYaw;
    float rasterPointerPitch;
    vec2 pointerPosition;
    float pointerLevel;
    float keyboardLevel;
};

vec3 rotateX(vec3 p, float a) {
    float c = cos(a), s = sin(a);
    return vec3(p.x, p.y * c - p.z * s, p.y * s + p.z * c);
}

vec3 rotateY(vec3 p, float a) {
    float c = cos(a), s = sin(a);
    return vec3(p.x * c - p.z * s, p.y, p.x * s + p.z * c);
}

vec3 rotateZ(vec3 p, float a) {
    float c = cos(a), s = sin(a);
    return vec3(p.x * c - p.y * s, p.x * s + p.y * c, p.z);
}

void main() {
    vec2 center = canvasSize * 0.5;
    float radius = min(canvasSize.x, canvasSize.y) * 0.34;
    vec2 local = qt_Vertex.xy - center;

    // Canvas is the event-driven detail raster. Apply only the camera delta
    // since that raster was built, keeping motion on the GPU between updates.
    float nowYaw = motionClock * 0.045;
    float oldYaw = rasterMotionClock * 0.045;
    float nowPitch = 0.20 + 0.22 * sin(motionClock * 6.28318530718 / 47.0);
    float oldPitch = 0.20 + 0.22 * sin(rasterMotionClock * 6.28318530718 / 47.0);
    float nowRoll = 0.16 * sin(motionClock * 6.28318530718 / 73.0 + 1.1);
    float oldRoll = 0.16 * sin(rasterMotionClock * 6.28318530718 / 73.0 + 1.1);
    vec3 p = vec3(local / radius, 0.0);
    p = rotateY(p, -(nowYaw - oldYaw));
    p = rotateX(p, nowPitch - oldPitch);
    p = rotateZ(p, nowRoll - oldRoll);
    p = rotateY(p, -(pointerYaw - rasterPointerYaw));
    p = rotateX(p, pointerPitch - rasterPointerPitch);
    float cameraPerspective = 3.6 / (3.6 + p.z);
    vec2 corrected = p.xy * radius * cameraPerspective;
    float agentBody = max(thoughtLevel, agentLevel);

    // A radial surface wave is confined to the sphere body, so the graph
    // deforms visibly while the sparse labels around its rim stay crisp.
    float radial = length(corrected) / radius;
    float body = 1.0 - smoothstep(0.94, 1.18, radial);
    vec2 direction = radial > 0.001 ? normalize(corrected) : vec2(0.0);
    float phase = radial * 18.8495559215 - elapsedTime * 1.96349540849;
    float ripple = sin(phase);
    corrected += direction * (42.0 * agentBody * body * ripple);
    vec2 eddy = vec2(sin(corrected.y / radius * 4.8 + elapsedTime * 0.83),
                     cos(corrected.x / radius * 4.1 - elapsedTime * 0.71));
    corrected += eddy * (13.0 * agentBody * body);

    // Add a broad traveling shear so thinking looks like a fluid surface wave,
    // rather than a uniform zoom. The existing GPU mesh carries the motion.
    float agentPhase = corrected.x / radius * 3.1 + corrected.y / radius * 1.9 - elapsedTime * 0.82;
    float agentSway = sin(agentPhase) + 0.45 * cos(corrected.y / radius * 4.2 - elapsedTime * 0.57);
    corrected += direction * (18.0 * agentLevel * body * agentSway);
    corrected += vec2(cos(agentPhase * 0.71), sin(agentPhase * 0.71))
                 * (8.0 * agentLevel * body * sin(agentPhase * 0.63));

    // Listening feedback stays subordinate to agent motion: a local pointer
    // ring and a broader keyboard wave fade through their own envelopes.
    vec2 pointerDelta = corrected / radius - pointerPosition;
    float pointerDistance = length(pointerDelta);
    float pointerPhase = pointerDistance * 13.0 - elapsedTime * 5.2;
    float pointerRing = exp(-abs(pointerPhase - 6.28318530718 * floor(pointerPhase / 6.28318530718 + 0.5)) * 1.6);
    corrected += (pointerDistance > 0.001 ? normalize(pointerDelta) : vec2(0.0))
                 * (pointerRing * pointerLevel * 4.5 * radius * 0.01 * body);
    float keyDistance = length(corrected) / radius;
    float keyRing = sin(keyDistance * 17.0 - elapsedTime * 3.0);
    corrected += direction * (keyRing * keyboardLevel * 2.4 * body);

    // A shared, shader-only breath makes AI activity legible across the full
    // sphere. It moves the existing mesh without rerasterizing Canvas nodes.
    float agentBreath = sin(elapsedTime * 1.04);
    corrected *= 1.0 + 0.075 * agentLevel * agentBreath;

    gl_Position = qt_Matrix * vec4(center + corrected, 0.0, 1.0);
    texCoord = qt_MultiTexCoord0;
}
