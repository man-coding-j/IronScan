import React from 'react';
import {interpolate} from 'remotion';
import {config, frames} from '../config';
import {C, pop, ramp, sans} from '../design';

const P = config.copy.phone;
const T = config.timing.import;
const panel: React.CSSProperties = {background:C.glass,border:`1px solid ${C.border}`,borderRadius:22,boxSizing:'border-box'};

export const Glyph = ({name,size=24,color='currentColor'}:{name:string;size?:number;color?:string}) => {
  const paths: Record<string,React.ReactNode> = {
    check:<path d="M5 12l4 4L19 6"/>, close:<path d="M6 6l12 12M6 18L18 6"/>,
    shield:<><path d="M12 2l8 3v6c0 5-4 8-8 11-4-3-8-6-8-11V5z"/><path d="M8 12l3 3 5-6"/></>,
    camera:<><path d="M3 7h4l2-3h6l2 3h4v14H3z"/><circle cx="12" cy="13" r="4"/></>,
    flip:<><path d="M3 7h4l2-3h6l2 3h4v14H3z"/><path d="M8 12a4 4 0 0 1 7-1l1 2m-1-4l1 4-4-1M16 16a4 4 0 0 1-7 1l-1-2"/></>,
    bolt:<path d="M14 2L5 14h6l-1 8 9-13h-6z"/>,
    photos:<><rect x="6" y="3" width="16" height="16" rx="3"/><path d="M3 8v13h14M7 16l5-5 4 3 3-3 2 2"/><circle cx="17" cy="7" r="1"/></>,
    home:<><path d="M2 11L12 2l10 9M5 9v13h14V9"/><path d="M9 22v-8h6v8"/></>,
    history:<><circle cx="12" cy="12" r="9"/><path d="M12 6v7H7"/></>,
    learn:<><rect x="4" y="3" width="16" height="19" rx="2"/><path d="M8 3v19M4 18h16"/></>,
    profile:<><circle cx="12" cy="7" r="4"/><path d="M3 22c0-11 18-11 18 0z"/></>,
    arrow:<path d="M3 12h18m-6-6l6 6-6 6"/>,
    calendar:<><rect x="3" y="5" width="18" height="17" rx="3"/><path d="M7 2v6m10-6v6M3 11h18m-14 4h1m4 0h1m4 0h1"/></>,
  };
  return <svg viewBox="0 0 24 24" width={size} height={size} fill="none" stroke={color} strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round">{paths[name]??paths.camera}</svg>;
};

const StatusBar = () => <div style={{height:62,position:'relative',fontWeight:600,fontSize:16,color:C.darkTeal}}>
  <span style={{position:'absolute',top:20,left:35}}>{P.time}</span>
  <div style={{position:'absolute',top:14,left:140,width:128,height:36,borderRadius:25,background:C.darkTeal}}/>
  <svg style={{position:'absolute',right:25,top:24}} width="64" height="16" viewBox="0 0 64 16" fill="none" stroke={C.darkTeal} strokeWidth="1.5"><path d="M0 6q9-9 18 0M4 9q5-5 10 0M8 12h2"/><rect x="28" y="2" width="27" height="12" rx="3"/><path d="M58 6v4"/><rect x="31" y="5" width="20" height="6" rx="1" fill={C.teal}/></svg>
</div>;

const Tabs = ({active}:{active:number}) => <div style={{position:'absolute',left:18,right:18,bottom:18,height:62,...panel,background:C.cream+'EB',borderRadius:38,display:'flex',alignItems:'center',justifyContent:'space-around',boxShadow:`0 10px 25px ${C.shadow}`}}>
  {P.tabs.map((label,i)=><div key={label} style={{width:68,height:54,borderRadius:32,display:'flex',alignItems:'center',justifyContent:'center',flexDirection:'column',gap:2,color:i===active?C.marigold:C.darkTeal,background:i===active?C.sand:'transparent',fontSize:10,fontWeight:600}}><Glyph name={['home','history','camera','learn','profile'][i]} size={24}/>{label}</div>)}
</div>;

const Canvas = ({children,active}:{children:React.ReactNode;active:number}) => <div data-illustrated-screen style={{position:'absolute',inset:0,background:C.sand,color:C.teal,fontFamily:sans,overflow:'hidden'}}>
  <svg viewBox="0 0 408 932" style={{position:'absolute',inset:0,width:'100%',height:'100%'}}><path d="M-30 180C120 230 170 55 310 126C150 240 225 360 430 365M430 450C80 305 85 640 308 655S310 920-30 776" fill="none" stroke={C.marigold} strokeWidth="3" opacity=".65"/></svg>
  <StatusBar/>{children}<Tabs active={active}/>
</div>;

// Original vector anatomical illustrations; no patient photos or external assets.
const TissueThumbnail = ({kind}:{kind:number}) => <svg viewBox="0 0 120 72" width="100%" height="100%">
  <rect width="120" height="72" rx="10" fill={C.blue}/>
  {kind===0&&<><path d="M9 36Q60-8 111 36Q60 80 9 36" fill={C.cream} stroke={C.teal} strokeWidth="2"/><circle cx="60" cy="34" r="17" fill={C.teal}/><circle cx="60" cy="34" r="7" fill={C.darkTeal}/><path d="M17 42Q60 72 103 42" fill="none" stroke={C.tissueRose} strokeWidth="8"/></>}
  {kind===1&&<><path d="M35 75V31C35-5 85-5 85 31V75" fill={C.tissueLight} stroke={C.teal} strokeWidth="2"/><path d="M43 34V27C43 3 77 3 77 27V34Q60 47 43 34" fill={C.nail} stroke={C.tissueRose} strokeWidth="2"/><path d="M45 47q15 8 30 0" fill="none" stroke={C.tissueRose} strokeWidth="2"/></>}
  {kind===2&&<><path d="M24 15Q60 3 96 15L88 43Q60 67 32 43Z" fill={C.darkTeal}/><path d="M41 29Q60 20 79 29L76 53C74 73 46 73 44 53Z" fill={C.tissueRose} stroke={C.teal} strokeWidth="2"/><path d="M60 30v23" stroke={C.tissueLight} strokeWidth="2"/></>}
</svg>;

const GlassControl = ({name}:{name:string}) => <div style={{width:41,height:41,borderRadius:25,display:'grid',placeItems:'center',color:C.cream,background:C.blue+'38',border:`1px solid ${C.border}`,backdropFilter:'blur(10px)'}}><Glyph name={name} size={22}/></div>;

export const ScanScreen = ({localFrame,mode}:{localFrame:number;mode:'live'|'import'}) => {
  const importing=mode==='import';
  const f=localFrame;
  const t=f/config.video.fps;
  const purge=importing?ramp(f,frames(T.purgeStart),frames(T.purgeDuration)):0;
  const hud=importing?pop(f,frames(T.hudStart)):0;
  const progress=importing?interpolate(f,[frames(T.progressStart),frames(T.progressEnd)],[0,1],{extrapolateLeft:'clamp',extrapolateRight:'clamp'}):0;
  const beam=0.5-0.5*Math.cos(t/T.beamPeriod*Math.PI*2);
  return <Canvas active={2}>
    <div style={{position:'absolute',top:77,left:22,right:22,display:'flex',justifyContent:'space-between',alignItems:'center'}}><Glyph name="close" size={25}/><div style={{fontSize:24,fontWeight:600}}>{P.scanTitle}</div><div style={{width:25}}/></div>
    <div style={{position:'absolute',left:20,right:20,top:122,height:74,...panel,display:'flex',alignItems:'center',justifyContent:'space-around'}}>
      {P.steps.map((step,i)=><div key={step} style={{textAlign:'center',width:116,fontSize:10.5,fontWeight:600}}><div style={{width:27,height:27,borderRadius:18,background:importing||i===0?C.marigold:C.blue,display:'grid',placeItems:'center',margin:'0 auto 7px'}}>{i+1}</div>{step}</div>)}
    </div>
    <div style={{position:'absolute',left:22,top:210,fontSize:18,fontWeight:600}}>{P.tissue}</div>
    <div style={{position:'absolute',left:22,top:235,fontSize:12,color:C.muted}}>{P.guide}</div>
    <div style={{position:'absolute',left:20,right:20,top:266,height:332,borderRadius:23,overflow:'hidden',background:`linear-gradient(145deg,${C.teal},${C.darkTeal})`,border:`1px solid ${C.border}`}}>
      {importing&&<div style={{position:'absolute',left:26,right:26,top:90,height:140,opacity:.65*(1-purge)}}><TissueThumbnail kind={0}/></div>}
      <div style={{position:'absolute',left:40,right:40,top:importing?107:146,height:79,borderRadius:'50%',border:`2.5px dashed ${C.marigold}`,opacity:importing?.4:1}}/>
      <div style={{position:'absolute',top:13,left:35,padding:'7px 13px',fontSize:11,fontWeight:600,borderRadius:24,background:C.darkTeal+'E8',color:C.cream}}>{P.align}</div>
      <div style={{position:'absolute',right:12,top:13,display:'flex',flexDirection:'column',gap:11}}><GlassControl name="flip"/><GlassControl name="bolt"/></div>
      {!importing&&<div style={{position:'absolute',bottom:15,width:'100%',textAlign:'center',fontSize:11,color:C.blue}}>{P.live}</div>}
      {importing&&<>
        <div style={{position:'absolute',left:0,right:0,top:25+beam*280,height:3,background:C.marigold,boxShadow:`0 0 15px 5px ${C.marigold}88`,opacity:hud*(1-purge)}}><div style={{position:'absolute',left:0,right:0,bottom:0,height:50,background:`linear-gradient(transparent,${C.marigold}55)`}}/></div>
        <div style={{position:'absolute',left:19,right:19,top:66,height:232,boxSizing:'border-box',padding:'17px 16px',borderRadius:23,background:C.teal+'E0',border:`1.5px solid ${C.marigold}`,backdropFilter:'blur(14px)',boxShadow:`0 12px 30px ${C.shadow}`,opacity:hud,transform:`scale(${.93+.07*hud})`,color:C.cream,textAlign:'center'}}>
          <div style={{fontSize:14,fontWeight:600}}>{purge>.7?P.purged:P.hudTitle}</div>
          <div style={{display:'flex',alignItems:'center',justifyContent:'center',gap:20,margin:'13px 0'}}>{[1,2,3].map((n,i)=><div key={n} style={{display:'flex',alignItems:'center',gap:4,color:C.marigold,opacity:.7+.3*Math.sin(t/T.nodePulsePeriod*Math.PI*2-i)}}><span style={{fontSize:16,fontWeight:600}}>{n}</span><Glyph name="check" size={16}/></div>)}</div>
          <div style={{height:6,borderRadius:10,background:C.blue+'40',overflow:'hidden'}}><div style={{height:'100%',width:`${progress*100}%`,borderRadius:10,background:C.marigold}}/></div>
          <div style={{fontSize:10.5,marginTop:5,color:C.marigold}}>{Math.round(progress*100)}%</div>
          <div style={{fontSize:13,lineHeight:1.4,marginTop:8,minHeight:37}}>{purge>.7?P.complete:P.running}</div>
          <div style={{marginTop:8,padding:'8px 7px',border:`1px solid ${C.marigold}80`,borderRadius:14,display:'flex',alignItems:'center',gap:7,background:C.darkTeal+'88'}}><Glyph name="shield" size={23} color={C.marigold}/><span style={{fontSize:10,lineHeight:1.4,textAlign:'left',flex:1}}>{P.privacy}</span></div>
          <div style={{fontSize:8.5,marginTop:7,color:C.blue}}>{P.privacyDetail}</div>
        </div>
      </>}
    </div>
    <div style={{position:'absolute',left:20,right:20,top:616,display:'flex',gap:10}}>{P.thumbnails.map((label,i)=>{
      const selected=importing?ramp(f,frames(T.selectStart+i*T.selectStagger),frames(T.selectReveal)):0;
      const imageOpacity=selected*(1-purge);
      return <div key={label} style={{width:116,textAlign:'center'}}><div style={{position:'relative',height:61,...panel,border:`${selected>0?2:1}px solid ${selected>0?C.marigold:C.border}`,borderRadius:13,padding:3,boxShadow:selected>0?`0 0 12px ${C.marigold}55`:undefined}}>
        <div style={{position:'absolute',inset:3,opacity:imageOpacity}}><TissueThumbnail kind={i}/></div>
        <div style={{position:'absolute',inset:0,display:'grid',placeItems:'center',opacity:1-imageOpacity,color:C.muted}}><Glyph name={purge>.5?'shield':'photos'} size={23}/></div>
        <div style={{position:'absolute',right:4,top:4,width:19,height:19,borderRadius:'50%',background:C.marigold,color:C.teal,display:'grid',placeItems:'center',opacity:selected}}><Glyph name="check" size={13}/></div>
      </div><div style={{fontSize:10.5,fontWeight:500,marginTop:7}}>{label}</div></div>;
    })}</div>
    <div style={{position:'absolute',left:32,right:32,top:714,height:43,borderRadius:28,border:`1.5px solid ${C.marigold}`,background:importing?C.marigold:C.glass,display:'flex',alignItems:'center',justifyContent:'center',gap:9,boxShadow:importing?`0 0 22px ${C.marigold}55`:undefined,fontSize:14,fontWeight:600}}><Glyph name="photos" size={20}/>{P.import}</div>
    <div style={{position:'absolute',top:770,left:24,right:24,textAlign:'center',fontSize:10,color:C.muted,lineHeight:1.5}}>{importing?(purge>.7?P.complete:P.ready):P.mockLabel}</div>
    <div style={{position:'absolute',left:32,right:32,top:805,height:35,borderRadius:20,background:C.teal,color:C.cream,display:'flex',alignItems:'center',justifyContent:'center',gap:8,fontSize:12,fontWeight:600}}><Glyph name="camera" size={17}/>{P.capture}</div>
  </Canvas>;
};

export const HistoryScreen = () => {
  const values=P.chartValues;
  const x=[76,185,294];
  const y=(value:number)=>157-(value-10)*20;
  const path=`M${x[0]} ${y(values[0])} C${x[0]+45} ${y(values[0])} ${x[1]-45} ${y(values[1])} ${x[1]} ${y(values[1])} S${x[2]-40} ${y(values[2])} ${x[2]} ${y(values[2])}`;
  return <Canvas active={1}>
    <div style={{position:'absolute',top:78,left:22,right:22,display:'flex',alignItems:'center',justifyContent:'space-between'}}><span style={{fontSize:30,fontWeight:600}}>{P.historyTitle}</span><Glyph name="calendar"/></div>
    <div style={{position:'absolute',top:126,left:20,right:20,...panel,padding:'11px 14px',fontSize:13,fontWeight:500,display:'flex',alignItems:'center',gap:9}}><span style={{width:8,height:8,borderRadius:5,background:C.marigold}}/>{P.sync}</div>
    <div style={{position:'absolute',left:22,top:186,fontSize:19,fontWeight:600}}>{P.chartTitle}</div>
    <div style={{position:'absolute',left:20,right:20,top:220,height:332,...panel,padding:16}}>
      <div style={{fontSize:26,fontWeight:600}}>{P.estimate}<span style={{fontSize:12,padding:'6px 11px',marginLeft:16,borderRadius:20,background:C.marigold+'33'}}>{P.severity}</span></div>
      <div style={{fontSize:10.5,color:C.muted,marginTop:5}}>{P.estimatedLabel}</div>
      <svg width="100%" height="203" viewBox="0 0 332 203" style={{marginTop:10,overflow:'visible',fontFamily:sans}}>
        <rect x="59" y={y(15.5)} width="258" height={y(12)-y(15.5)} fill={C.blue}/>
        {P.axisValues.map(value=><g key={value}><path d={`M59 ${y(value)}H317`} stroke={C.white} strokeWidth="1"/><text x="0" y={y(value)+4} fontSize="10" fill={C.muted}>{value.toFixed(1)} g/dL</text></g>)}
        <path d={path} fill="none" stroke={C.marigold} strokeWidth="3.5"/>
        {values.map((value,i)=><g key={value}><circle cx={x[i]} cy={y(value)} r="5" fill={C.marigold} stroke={C.cream} strokeWidth="2"/><text x={x[i]} y={y(value)-14} textAnchor="middle" fill={C.teal} fontSize="11" fontWeight="600">{value.toFixed(1)} g/dL</text><text x={x[i]} y="189" textAnchor="middle" fill={C.muted} fontSize="10">{P.chartDates[i]}</text></g>)}
      </svg>
      <div style={{fontSize:10.5,color:C.muted,marginTop:9}}>{P.reference}</div>
    </div>
    <div style={{position:'absolute',top:573,left:20,right:20,height:47,borderRadius:26,background:C.teal,color:C.cream,fontSize:15,fontWeight:600,display:'flex',gap:14,justifyContent:'center',alignItems:'center'}}>{P.export}<Glyph name="arrow" size={18}/></div>
    <div style={{position:'absolute',top:643,left:22,right:22,display:'flex',justifyContent:'space-between',alignItems:'center'}}><span style={{fontSize:20,fontWeight:600}}>{P.recent}</span><span style={{fontSize:12}}>{P.startScan}</span></div>
    {[...values].reverse().map((value,i)=><div key={value} style={{position:'absolute',top:681+i*54,left:20,right:20,height:47,...panel,padding:'8px 13px',display:'flex',alignItems:'center',gap:10}}><Glyph name="history" size={23}/><div style={{fontSize:12,fontWeight:600,flex:1}}>{P.rowLabel}<div style={{fontSize:10,fontWeight:400,color:C.muted,marginTop:3}}>{P.chartDates[2-i]}</div></div><span style={{fontSize:14,fontWeight:600}}>{value.toFixed(1)} g/dL</span></div>)}
  </Canvas>;
};
