import React from 'react';
import {useCurrentFrame} from 'remotion';
import {config, frames, sceneFrames} from '../config';
import {BrandMark, C, Eyebrow, pop, ramp, Ribbon, Scene, serif} from '../design';

export const Opening = () => {
  const f = useCurrentFrame();
  const title = pop(f, frames(config.timing.titleDelay));
  const tagline = ramp(f, frames(config.timing.taglineDelay), frames(config.timing.taglineReveal));
  return <Scene duration={sceneFrames.opening} first>
    <Ribbon/>
    <div style={{position: 'absolute', top: 92, left: 104}}><Eyebrow>{config.copy.eyebrow}</Eyebrow></div>
    <div style={{position: 'absolute', top: 92, right: 104, opacity: 0.6}}><Eyebrow>{config.copy.tutorial}</Eyebrow></div>
    <div style={{position: 'absolute', inset: 0, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', paddingBottom: 70}}>
      <div style={{opacity: title, transform: `translateY(${(1-title)*35}px) scale(${0.91+title*0.09})`, textAlign: 'center'}}>
        <div style={{display: 'flex', justifyContent: 'center', marginBottom: 35}}><BrandMark/></div>
        <h1 style={{fontFamily: serif, fontSize: config.type.hero, fontWeight: 400, lineHeight: 1.05, letterSpacing: -9, margin: 0}}>{config.copy.name}</h1>
      </div>
      <div style={{fontSize: config.type.body, maxWidth: 1480, textAlign: 'center', lineHeight: 1.4, marginTop: 34, opacity: tagline, transform: `translateY(${20*(1-tagline)}px)`}}>{config.copy.tagline}</div>
    </div>
    <div style={{position: 'absolute', bottom: 65, width: '100%', textAlign: 'center', fontSize: 17, letterSpacing: 4, color: C.muted}}>{config.copy.prototype}</div>
  </Scene>;
};
