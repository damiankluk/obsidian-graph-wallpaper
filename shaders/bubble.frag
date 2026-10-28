#version 440
layout(location = 0) in vec2 texCoord;
layout(location = 0) out vec4 fragColor;

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

layout(binding = 1) uniform sampler2D source;

void main() {
    vec4 graph = texture(source, texCoord);
    float bluePath = smoothstep(graph.r * 1.12, graph.r * 1.48, graph.b)
                   * smoothstep(graph.r * 1.04, graph.r * 1.30, graph.g)
                   * smoothstep(0.015, 0.12, graph.a);
    float phase = (texCoord.x + texCoord.y * 0.41) * 25.0 - elapsedTime * (1.4 + thoughtLevel * 2.0);
    float travelingGlow = smoothstep(-0.15, 0.9, sin(phase)) * (0.28 + thoughtLevel * 0.72);
    graph.rgb += vec3(0.26, 0.54, 0.90) * bluePath * travelingGlow * graph.a;
    float agentFlow = smoothstep(-0.15, 0.9, sin(phase + 0.8));
    graph.rgb += vec3(0.40, 0.72, 1.25) * bluePath * agentLevel * agentFlow * graph.a;
    fragColor = graph * qt_Opacity;
}
