VARYING vec4 graphColor;
VARYING vec2 graphUv;
VARYING float graphNodeIndex;
VARYING float graphDepth;

vec3 rotateY(vec3 p, float a)
{
    float c = cos(a), s = sin(a);
    return vec3(p.x * c - p.z * s, p.y, p.x * s + p.z * c);
}

vec3 rotateX(vec3 p, float a)
{
    float c = cos(a), s = sin(a);
    return vec3(p.x, p.y * c - p.z * s, p.y * s + p.z * c);
}

vec3 rotateZ(vec3 p, float a)
{
    float c = cos(a), s = sin(a);
    return vec3(p.x * c - p.y * s, p.x * s + p.y * c, p.z);
}

void MAIN()
{
    vec3 p = rotateZ(rotateX(rotateY(VERTEX, uYaw), uPitch), uRoll);
    float radius = length(p);
    vec3 direction = radius > 0.001 ? p / radius : vec3(0.0, 0.0, 1.0);
    float normalizedRadius = radius / 440.0;
    float body = smoothstep(0.08, 0.42, normalizedRadius)
               * (1.0 - smoothstep(1.35, 1.9, normalizedRadius));

    float modeA = sin(dot(direction, vec3(2.4, 1.2, -1.7)) + uWavePhaseA);
    float modeB = sin(dot(direction, vec3(-1.3, 2.1, 1.8)) + uWavePhaseB);
    float membrane = modeA * 0.62 + modeB * 0.38;
    float radialRipple = sin(normalizedRadius * 18.85 - uWavePhaseA * 1.6);
    float agentMotion = uAgent * body;
    float radialDisplacement = 440.0 * agentMotion
        * (0.045 * membrane + 0.020 * radialRipple + 0.028 * sin(uBreathPhase));
    vec3 tangent = normalize(cross(direction, vec3(0.0, 0.0, 1.0)) + vec3(0.0001, 0.0, 0.0));
    p += direction * radialDisplacement;
    p += tangent * (440.0 * agentMotion * 0.014 * modeA * modeB);

    float pointerDistance = length(p - uPointerPosition);
    float pointerWave = sin(pointerDistance * 0.032 - uPointerPhase);
    float keyboardWave = sin(normalizedRadius * 17.0 - uFlowPhase * 1.35);
    float listen = 1.0 - uAgent * 0.68;
    p += direction * (body * listen * 440.0
        * (0.0055 * uPointerLevel * pointerWave + 0.005 * uKeyboardLevel * keyboardWave));

    VERTEX = p;
    POSITION = MODELVIEWPROJECTION_MATRIX * vec4(p, 1.0);
    graphColor = COLOR;
    graphUv = UV0;
    graphNodeIndex = (uKind > 0.5 ? UV0.x : UV0.y) * uNodeCount;
    graphDepth = p.z;
}
