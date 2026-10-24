import React, {useEffect, useState} from 'react';
import {AbsoluteFill, continueRender, delayRender, Img, interpolate, staticFile, useCurrentFrame} from 'remotion';
import {config, frames, sceneFrames} from '../config';
import {C, Eyebrow, glass, Icon, pop, ramp, Ribbon, Scene, serif} from '../design';

const Screenshot = ({file}: {file: string}) => {
  const [handle] = useState(()=>delayRender(`Reading screenshot dimensions: ${file}`));
  const [ratio,setRatio] = useState<number | null>(null);
  useEffect(()=>{if(ratio !== null) continueRender(handle);},[ratio,handle]);
  // Fit the entire capture into the available screen before applying the gentle zoom.
  // The frame ratio is independent of the screenshot's dimensions.
  const frameRatio = 408/932;
  return <div style={{position:'relative',width:ratio && ratio < frameRatio ? `${ratio/frameRatio*100}%` : '100%',height:ratio && ratio >= frameRatio ? `${frameRatio/ratio*100}%` : '100%'}}>
    <Img src={staticFile(config.assets.screenshots+file)} onLoad={event=>setRatio(event.currentTarget.naturalWidth/event.currentTarget.naturalHeight)} style={{display:'block',width:'100%',height:'100%',objectFit:'contain'}}/>
  </div>;
};

const Phone = () => {
  const f = useCurrentFrame();
  const enter = pop(f);
  return <div style={{position:'absolute', left:744, top:62, width:432, height:956, transform:`translateY(${55*(1-enter)}px) scale(${0.97+0.03*enter})`, opacity:enter}}>
    <div style={{position:'absolute', left:-4, top:185, width:5, height:65, borderRadius:3, background:C.teal}}/>
    <div style={{position:'absolute', right:-4, top:208, width:5, height:95, borderRadius:3, background:C.teal}}/>
    <div style={{position:'absolute', inset:0, background:C.teal, borderRadius:66, boxShadow:`0 35px 70px ${C.shadow}, inset 0 0 0 2px ${C.border}`, padding:12}}>
      <div style={{position:'relative', width:'100%', height:'100%', overflow:'hidden', borderRadius:55, background:C.sand}}>
        {(() => {
          const dwell = frames(config.timing.screenshot);
          const transition = frames(config.timing.screenshotSlide);
          const slot = dwell + transition;
          const current = Math.min(config.copy.screens.length - 1, Math.floor(f/slot));
          const local = f-current*slot;
          const outgoing = current < config.copy.screens.length-1 ? ramp(local,slot-transition/2,transition/2) : 0;
          const incoming = current === 0 ? 1 : ramp(local,0,transition/2);
          const zoom = interpolate(local,[0,slot],[0.985,1],{extrapolateLeft:'clamp',extrapolateRight:'clamp'});
          // Exactly one screenshot is mounted. Fade fully out before changing the source.
          return <AbsoluteFill key={current} style={{opacity:incoming*(1-outgoing),transform:`scale(${zoom})`,display:'flex',alignItems:'center',justifyContent:'center'}}>
            <Screenshot file={config.copy.screens[current].file}/>
          </AbsoluteFill>;
        })()}
      </div>
    </div>
  </div>;
};

export const Showcase = () => {
  const f = useCurrentFrame();
  const hold = frames(config.timing.screenshot)+frames(config.timing.screenshotSlide);
  const current = Math.min(config.copy.screens.length-1, Math.floor(f/hold));
  const local = f-current*hold;
  const p = ramp(local,0,frames(config.timing.captionReveal));
  return <Scene duration={sceneFrames.showcase}>
    <Ribbon subtle/>
    <div style={{position:'absolute',width:850,height:850,borderRadius:'50%',background:`radial-gradient(circle, ${C.blue} 0%, ${C.blue}00 70%)`,left:535,top:150}}/>
    <div style={{position:'absolute',left:105,top:305,width:550}}>
      <Eyebrow>{config.copy.showcaseEyebrow}</Eyebrow>
      <h2 style={{fontFamily:serif,fontWeight:400,fontSize:100,lineHeight:1.1,letterSpacing:-4,whiteSpace:'pre-line',margin:'32px 0'}}>{config.copy.showcaseHeading}</h2>
      <div style={{fontSize:25,color:C.muted}}>{config.copy.showcaseDetail}</div>
      <div style={{fontSize:19,lineHeight:1.5,color:C.muted,marginTop:32,maxWidth:470}}>{config.copy.sampleNotice}</div>
    </div>
    <Phone/>
    <div style={{position:'absolute',left:1250,top:415,width:560}}>
      <div style={{fontSize:23,letterSpacing:4,color:C.muted,marginBottom:25}}>{String(current+1).padStart(2,'0')} / {String(config.copy.screens.length).padStart(2,'0')}</div>
      <div style={{...glass,padding:'28px 30px',height:245,boxSizing:'border-box',opacity:p,transform:`translateX(${25*(1-p)}px)`}}>
        <div style={{fontFamily:serif,fontSize:48,lineHeight:1.2}}>{config.copy.screens[current].caption}</div>
        <div style={{color:C.marigold,marginTop:18}}><Icon kind="arrow" size={45}/></div>
      </div>
      <div style={{display:'flex',gap:13,marginTop:35}}>{config.copy.screens.map((s,i)=><div key={s.file} style={{width:87,height:4,borderRadius:4,background:C.glass,overflow:'hidden'}}><div style={{height:'100%',background:C.marigold,width:`${i<current ? 100 : i===current ? Math.min(100,local/hold*100) : 0}%`}}/></div>)}</div>
    </div>
  </Scene>;
};
