import React from 'react';
import {Composition, registerRoot} from 'remotion';
import {config, totalFrames} from './config';
import {Intro} from './Intro';

const Root = () => React.createElement(Composition, {
  id: config.video.id,
  component: Intro,
  width: config.video.width,
  height: config.video.height,
  fps: config.video.fps,
  durationInFrames: totalFrames,
});
registerRoot(Root);
