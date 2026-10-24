import React from 'react';
import {AbsoluteFill, Sequence} from 'remotion';
import {config, sceneFrames} from './config';
import {Opening} from './scenes/Opening';
import {Problem} from './scenes/Problem';
import {Process} from './scenes/Process';
import {Showcase} from './scenes/Showcase';
import {Closing} from './scenes/Closing';

export const Intro = () => {
  const components = [Opening,Problem,Process,Showcase,Closing];
  let start = 0;
  return <AbsoluteFill style={{background:config.colors.sand}}>
    {Object.values(sceneFrames).map((duration,i)=>{
      const from=start;
      start+=duration;
      const Component=components[i];
      return <Sequence key={i} from={from} durationInFrames={duration}><Component/></Sequence>;
    })}
  </AbsoluteFill>;
};
