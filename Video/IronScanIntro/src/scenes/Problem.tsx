import React from 'react';
import {useCurrentFrame} from 'remotion';
import {config, frames, sceneFrames} from '../config';
import {C, Eyebrow, ramp, Ribbon, Scene, serif} from '../design';

export const Problem = () => {
  const f = useCurrentFrame();
  return <Scene duration={sceneFrames.problem}>
    <Ribbon subtle/>
    <div style={{position: 'absolute', left: 140, top: 165}}><Eyebrow>{config.copy.problemEyebrow}</Eyebrow></div>
    <div style={{position: 'absolute', left: 140, top: 285, width: 1600, fontFamily: serif, fontSize: 66, lineHeight: 1.22, letterSpacing: -2}}>
      {config.copy.problem.split(/\s+/).map((word, i) => {
        const p = ramp(f, frames(config.timing.wordStart) + frames(config.timing.wordStagger)*i, frames(config.timing.wordReveal));
        return <span key={i} style={{display: 'inline-block', opacity: p, transform: `translateY(${24*(1-p)}px)`, marginRight: 15}}>{word}</span>;
      })}
    </div>
    {<div style={{position: 'absolute', left: 140, bottom: 120, color: C.muted, width: 1590, lineHeight: 1.5, fontSize: 24, opacity: ramp(f, frames(config.timing.noteDelay), frames(config.timing.noteReveal))}}>{config.copy.problemNote}</div>}
  </Scene>;
};
