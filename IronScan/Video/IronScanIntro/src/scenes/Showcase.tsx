import React, {useEffect, useState} from 'react';
import {AbsoluteFill, cancelRender, continueRender, delayRender, Img, interpolate, staticFile, useCurrentFrame} from 'remotion';
import {carousel, config, frames, sceneFrames} from '../config';
import {C, Eyebrow, glass, Icon, pop, ramp, Ribbon, Scene, serif} from '../design';
import {HistoryScreen, ScanScreen} from './PhoneScreens';

const Screenshot = ({file}:{file:string}) => {
  const [handle]=useState(()=>delayRender(`Reading screenshot dimensions: ${file}`));
  const [ratio,setRatio]=useState<number|null>(null);
  useEffect(()=>{if(ratio!==null)continueRender(handle);},[ratio,handle]);
  const frameRatio=408/932;
  return <div style={{position:'relative',width:ratio&&ratio<frameRatio?`${ratio/frameRatio*100}%`:'100%',height:ratio&&ratio>=frameRatio?`${frameRatio/ratio*100}%`:'100%'}}>
    <Img src={staticFile(config.assets.screenshots+file)} onError={()=>cancelRender(new Error(`Missing screenshot: ${file}`))} onLoad={e=>setRatio(e.currentTarget.naturalWidth/e.currentTarget.naturalHeight)} style={{display:'block',width:'100%',height:'100%',objectFit:'contain'}}/>
  </div>;
};

export const carouselState=(frame:number)=>{
  let index=0;
  for(let i=0;i<carousel.length;i++)if(frame>=carousel[i].start)index=i;
  const local=frame-carousel[index].start;
  return {index,local,blend:index===0?1:ramp(local,0,frames(config.timing.screenshotSlide))};
};

const PhoneContent=({index,localFrame}:{index:number;localFrame:number})=>{
  const screen=carousel[index];
  if(screen.kind==='import'||screen.kind==='live')return <ScanScreen localFrame={localFrame} mode={screen.kind}/>;
  if(screen.kind==='history')return <HistoryScreen/>;
  return <Screenshot file={screen.file!}/>;
};

const Phone=()=>{
  const f=useCurrentFrame();
  const {index,local,blend}=carouselState(f);
  const enter=pop(f);
  const layers=index>0&&blend<1
    ? [{index:index-1,local:carousel[index-1].frames-1,opacity:1},{index,local,opacity:blend}]
    : [{index,local,opacity:1}];
  return <div style={{position:'absolute',left:744,top:62,width:432,height:956,transform:`translateY(${55*(1-enter)}px) scale(${.97+.03*enter})`,opacity:enter}}>
    <div style={{position:'absolute',left:-4,top:185,width:5,height:65,borderRadius:3,background:C.teal}}/>
    <div style={{position:'absolute',right:-4,top:208,width:5,height:95,borderRadius:3,background:C.teal}}/>
    <div style={{position:'absolute',inset:0,background:C.teal,borderRadius:66,boxShadow:`0 35px 70px ${C.shadow}, inset 0 0 0 2px ${C.border}`,padding:12}}>
      <div style={{position:'relative',width:'100%',height:'100%',overflow:'hidden',borderRadius:55,background:C.sand}}>
        {layers.map(layer=>{
          const zoom=interpolate(layer.local,[0,carousel[layer.index].frames],[.985,1],{extrapolateLeft:'clamp',extrapolateRight:'clamp'});
          // The outgoing screen remains fully opaque underneath the incoming one.
          // Source-over yields previous*(1-blend) + next*blend, never an empty frame.
          return <AbsoluteFill key={layer.index} data-phone-layer={layer.index} style={{opacity:layer.opacity,background:C.sand,transform:`scale(${zoom})`,display:'flex',alignItems:'center',justifyContent:'center'}}>
            <PhoneContent index={layer.index} localFrame={layer.local}/>
          </AbsoluteFill>;
        })}
      </div>
    </div>
  </div>;
};

export const Showcase=()=>{
  const f=useCurrentFrame();
  const {index,local}=carouselState(f);
  const screen=carousel[index];
  const p=ramp(local,0,frames(config.timing.captionReveal));
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
    <div style={{position:'absolute',left:1250,top:345,width:560}}>
      <div style={{fontSize:23,letterSpacing:4,color:C.muted,marginBottom:25}}>{String(index+1).padStart(2,'0')} / {String(carousel.length).padStart(2,'0')}</div>
      <div style={{...glass,padding:'28px 30px',height:340,boxSizing:'border-box'}}>
        <div style={{opacity:p,transform:`translateX(${25*(1-p)}px)`}}>
        <div style={{fontFamily:serif,fontSize:46,lineHeight:1.15}}>{screen.caption}</div>
        {screen.subtitle&&<div style={{fontSize:22,lineHeight:1.45,marginTop:18,color:C.muted}}>{screen.subtitle}</div>}
        {screen.kind==='import'&&<div style={{fontSize:16,lineHeight:1.45,marginTop:17,color:C.muted}}>{config.copy.phone.privacyQualification}</div>}
        {!screen.subtitle&&<div style={{color:C.marigold,marginTop:18}}><Icon kind="arrow" size={45}/></div>}
        </div>
      </div>
      <div style={{display:'flex',gap:12,marginTop:30}}>{carousel.map((s,i)=><div key={s.short} style={{flex:1,height:4,borderRadius:4,background:C.glass,overflow:'hidden'}}><div style={{height:'100%',background:C.marigold,width:`${i<index?100:i===index?Math.min(100,local/s.frames*100):0}%`}}/></div>)}</div>
    </div>
  </Scene>;
};
