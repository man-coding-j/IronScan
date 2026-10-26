import React from 'react';
import {useCurrentFrame} from 'remotion';
import {config, frames, sceneFrames} from '../config';
import {BrandMark, C, ramp, Ribbon, Scene, serif} from '../design';

export const Closing = () => {
  const f = useCurrentFrame();
  const p = ramp(f,0,frames(config.timing.closingReveal));
  return <Scene duration={sceneFrames.closing} last>
    <Ribbon subtle/>
    <div style={{position:'absolute',inset:0,display:'flex',alignItems:'center',justifyContent:'center',flexDirection:'column',opacity:p,transform:`translateY(${18*(1-p)}px)`}}>
      <BrandMark/>
      <h2 style={{fontFamily:serif,fontWeight:400,fontSize:100,letterSpacing:-4,margin:'46px 0 32px'}}>{config.copy.closing}</h2>
      <p style={{fontSize:27,color:C.muted,margin:0}}>{config.copy.disclaimer}</p>
    </div>
  </Scene>;
};
