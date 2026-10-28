VARYING vec4 graphColor;
VARYING vec2 graphUv;
VARYING float graphNodeIndex;
VARYING float graphDepth;

void MAIN()
{
    if (uKind > 0.5) {
        float focused = step(abs(graphNodeIndex - uFocusIndex), 0.5);
        float changed = max(max(step(abs(graphNodeIndex - uChangedA), 0.5),
                                step(abs(graphNodeIndex - uChangedB), 0.5)),
                                step(abs(graphNodeIndex - uChangedC), 0.5));
        float breath = 0.5 + 0.5 * sin(uBreathPhase);
        vec3 color = mix(graphColor.rgb, vec3(1.0, 0.91, 0.72), changed * 0.75);
        color = mix(color, vec3(0.88, 0.96, 1.0), focused * 0.8);
        float glow = 0.86 + 0.12 * breath + 0.28 * uAgent * (0.4 + 0.6 * breath);
        float nodeDepth = mix(0.18, 1.0, smoothstep(-120.0, 180.0, graphDepth));
        FRAGCOLOR = vec4(color * glow, graphColor.a * nodeDepth);
        return;
    }

    float sourceIndex = graphUv.y * uNodeCount;
    float targetIndex = graphColor.r * uNodeCount;
    float sourceFocused = step(abs(sourceIndex - uFocusIndex), 0.5);
    float targetFocused = step(abs(targetIndex - uFocusIndex), 0.5);
    float changedEdge = max(max(max(step(abs(sourceIndex - uChangedA), 0.5),
                                     step(abs(targetIndex - uChangedA), 0.5)),
                                 max(step(abs(sourceIndex - uChangedB), 0.5),
                                     step(abs(targetIndex - uChangedB), 0.5))),
                             max(step(abs(sourceIndex - uChangedC), 0.5),
                                 step(abs(targetIndex - uChangedC), 0.5)));
    float focusEdge = max(max(sourceFocused, targetFocused), changedEdge);

    // Only about 8% of links carry a traveling pulse at once. The rest stay
    // faintly visible, so the sphere keeps its network shape without becoming
    // a solid starburst. The seed is stable for each edge between refreshes.
    float selectedNeuron = step(0.92, graphColor.b);
    float pulsePhase = fract(graphUv.x - uFlowPhase * 0.08 + graphColor.b);
    float pulseDistance = min(pulsePhase, 1.0 - pulsePhase);
    float pulse = 1.0 - smoothstep(0.02, 0.09, pulseDistance);
    float listening = max(uPointerLevel, uKeyboardLevel);
    float agentActivity = clamp(uAgent * 1.35, 0.0, 1.0);
    float activity = max(agentActivity, listening * 0.45);
    // Keep a dim trace along a selected link, then let a brighter current
    // travel over it. This reads as a path activating instead of isolated
    // pinpricks that disappear at native monitor resolution.
    float travelingNeuron = selectedNeuron * activity * (0.72 + 0.28 * pulse);
    float highlight = max(focusEdge, travelingNeuron);

    float depthVisibility = mix(0.26, 1.0, smoothstep(-120.0, 180.0, graphDepth));
    float hubVisibility = mix(0.58, 1.0, graphColor.g);
    vec3 baseColor = vec3(0.12, 0.32, 0.56);
    vec3 neuronColor = vec3(0.55, 0.96, 1.0);
    vec3 linkColor = mix(baseColor, neuronColor, highlight);
    // The unselected network is only a trace; selected neuron paths carry
    // nearly all visible link energy.
    float alpha = graphColor.a * (0.04 + 0.96 * highlight)
                * depthVisibility * hubVisibility;
    float brightness = 1.05 + 2.10 * highlight;
    FRAGCOLOR = vec4(linkColor * brightness, min(0.72, alpha));
}
