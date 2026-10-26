import React from 'react';
import {AbsoluteFill, Easing, interpolate, spring, useCurrentFrame, staticFile, Img} from 'remotion';
import {loadFont as loadSerif} from '@remotion/google-fonts/Fraunces';
import {loadFont as loadSans} from '@remotion/google-fonts/DMSans';
import {config, frames} from './config';

export const serif = loadSerif('normal', {weights: ['400', '500'], subsets: ['latin']}).fontFamily;
export const sans = loadSans('normal', {weights: ['400', '500', '600'], subsets: ['latin']}).fontFamily;
export const C = config.colors;
export const ease = Easing.bezier(0.22, 1, 0.36, 1);
export const ramp = (frame: number, start: number, duration: number) => interpolate(frame, [start, start + duration], [0, 1], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp', easing: ease});
export const pop = (frame: number, delay = 0) => spring({frame: frame - delay, fps: config.video.fps, config: {damping: 22, stiffness: 100, mass: 0.8}});
export const glass: React.CSSProperties = {background: C.glass, border: `1.5px solid ${C.border}`, boxShadow: `0 18px 65px ${C.shadow}`, backdropFilter: 'blur(20px)', borderRadius: 36};

export const Eyebrow: React.FC<React.PropsWithChildren> = ({children}) => <div style={{fontFamily: sans, fontSize: config.type.small, fontWeight: 600, letterSpacing: 5, textTransform: 'uppercase'}}>{children}</div>;

export const Ribbon: React.FC<{subtle?: boolean}> = ({subtle = false}) => {
  const f = useCurrentFrame();
  const draw = ramp(f, 0, frames(config.timing.ribbon));
  const wave = Math.sin(f / frames(config.timing.ribbonLoop) * Math.PI * 2) * 9;
  return <svg viewBox="0 0 1920 1080" style={{position: 'absolute', inset: 0, width: '100%', height: '100%', transform: `translateY(${wave}px)`, opacity: subtle ? 0.35 : 0.85}}>
    <path d="M-160 870 C230 500 460 1120 780 852 S1190 380 1430 480 S1820 490 2050 110" fill="none" stroke={C.marigold} strokeWidth="9" strokeLinecap="round" pathLength="1" strokeDasharray="1" strokeDashoffset={1 - draw}/>
    <path d="M-120 904 C230 534 460 1154 780 886 S1190 414 1430 514 S1820 524 2050 144" fill="none" stroke={C.marigold} strokeWidth="2" strokeLinecap="round" pathLength="1" strokeDasharray="1" strokeDashoffset={1 - ramp(f, frames(config.timing.ribbonEchoDelay), frames(config.timing.ribbon))}/>
  </svg>;
};

export const Scene: React.FC<React.PropsWithChildren<{duration: number; first?: boolean; last?: boolean}>> = ({children, duration, first, last}) => {
  const f = useCurrentFrame();
  const t = frames(config.timing.transition);
  const opacity = (first ? 1 : ramp(f, 0, t)) * (last ? 1 : 1 - ramp(f, duration - t, t));
  return <AbsoluteFill style={{opacity, color: C.teal, fontFamily: sans}}>{children}</AbsoluteFill>;
};

// All icons are original inline SVG geometry; no external icon pack or brand marks.
export const Icon: React.FC<{kind: string; size?: number}> = ({kind, size = 90}) => <svg width={size} height={size} viewBox="0 0 100 100" fill="none" stroke="currentColor" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round">
  {kind === 'eye' && <><path d="M9 50 Q50 8 91 50 Q50 92 9 50Z"/><circle cx="50" cy="49" r="15"/><path d="M20 65 Q50 88 80 65" stroke={C.marigold} strokeWidth="5"/></>}
  {kind === 'nail' && <><path d="M29 86 V38 C29 6 71 6 71 38 V86"/><path d="M36 43 V34 C36 14 64 14 64 34 V43 Q50 51 36 43Z" fill={C.blue}/><path d="M37 43 Q50 50 63 43" stroke={C.marigold} strokeWidth="5"/><path d="M29 70 Q50 76 71 70"/></>}
  {kind === 'tongue' && <><path d="M18 28 Q50 10 82 28 L77 57 Q50 86 23 57Z"/><path d="M32 43 Q50 34 68 43 L66 70 C64 94 36 94 34 70Z" fill={C.sand}/><path d="M50 47 V69" stroke={C.marigold} strokeWidth="5"/></>}
  {kind === 'chip' && <><rect x="24" y="24" width="52" height="52" rx="12"/><path d="M38 50 L46 59 L63 39" stroke={C.marigold} strokeWidth="5"/>{[34,50,66].map(n=><React.Fragment key={n}><path d={`M${n} 14 V24 M${n} 76 V86 M14 ${n} H24 M76 ${n} H86`}/></React.Fragment>)}</>}
  {kind === 'arrow' && <path d="M20 50 H80 M60 30 L80 50 L60 70"/>}
</svg>;

export const BrandMark = () => config.assets.useLogo ? <Img src={staticFile(config.assets.logo)} style={{width: 100, height: 100, objectFit: 'contain'}}/> : <div style={{width: 72, height: 7, borderRadius: 10, background: C.marigold}}/>;
