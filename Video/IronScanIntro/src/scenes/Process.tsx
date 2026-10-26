import React from 'react';
import {useCurrentFrame} from 'remotion';
import {config, frames, sceneFrames} from '../config';
import {C, Eyebrow, glass, Icon, pop, ramp, Ribbon, Scene, serif} from '../design';

export const Process = () => {
  const f = useCurrentFrame();
  const ai = pop(f, frames(config.timing.aiDelay));
  const flow = ramp(f, frames(config.timing.flowDelay), frames(config.timing.flowReveal));
  return <Scene duration={sceneFrames.process}>
    <Ribbon subtle/>
    <div style={{position: 'absolute', left: 110, top: 115}}><Eyebrow>{config.copy.processEyebrow}</Eyebrow><h2 style={{fontFamily: serif, fontSize: config.type.title, fontWeight: 400, letterSpacing: -4, margin: '22px 0'}}>{config.copy.processHeading}</h2></div>
    <div style={{position:'absolute',left:110,top:310,padding:'10px 24px',borderRadius:26,background:C.blue+'B3',border:`1px solid ${C.border}`,fontSize:23,fontWeight:500}}>{config.copy.acquisition}</div>
    <svg viewBox="0 0 1920 1080" style={{position: 'absolute', inset: 0}}>
      {[0,1,2].map(i=><g key={i} opacity={flow}><path d={`M${272+i*366} 697 V758 Q${272+i*366} 790 ${302+i*366} 790 H1225 Q1265 790 1265 750 V638 H1322`} fill="none" stroke={C.teal} strokeWidth="3" pathLength="1" strokeDasharray="1" strokeDashoffset={1-flow}/></g>)}
      <path d="M1308 626 L1322 638 L1308 650" fill="none" stroke={C.teal} strokeWidth="3" opacity={flow}/>
    </svg>
    {config.copy.steps.map((step,i)=>{
      const p=pop(f, frames(config.timing.cardStart)+frames(config.timing.cardStagger)*i);
      return <div key={step.title} style={{...glass, position: 'absolute', left: 110+i*366, top: 383, width: 326, height: 314, padding: '36px 25px', boxSizing: 'border-box', opacity: p, transform: `translateY(${70*(1-p)}px)`}}>
        <div style={{color:C.teal, marginBottom: 28}}><Icon kind={step.icon}/></div>
        <div style={{fontSize: 28, fontWeight: 600, letterSpacing: -0.7, whiteSpace: 'nowrap'}}>{step.title}</div>
        <div style={{fontSize: 23, color:C.muted, marginTop: 13}}>{step.detail}</div>
      </div>;
    })}
    <div style={{...glass, background: C.teal, color: C.cream, borderColor: C.teal, position: 'absolute', left: 1325, top: 383, width: 480, height: 314, boxSizing: 'border-box', padding: '32px 38px', opacity: ai, transform:`translateY(${45*(1-ai)}px)`}}>
      <div style={{display: 'flex', alignItems:'center', gap: 20}}><Icon kind="chip" size={65}/><div style={{fontSize: 32, fontWeight: 500}}>{config.copy.ai}</div></div>
      <div style={{height: 1, background: C.glass, margin: '22px 0'}}/>
      <div style={{fontFamily:serif,fontSize: 37, lineHeight: 1.25}}>{config.copy.aiDetail}<br/><span style={{color: C.marigold}}>{config.copy.aiRisk}</span></div>
      <div style={{fontSize: 19, opacity: 0.72, marginTop: 16}}>{config.copy.aiFootnote}</div>
    </div>
    <div style={{position:'absolute',left:110,right:110,top:880,textAlign:'center',fontSize:26,color:C.muted,opacity:ai}}>{config.copy.techStack}</div>
  </Scene>;
};
