// The single editorial control panel. Durations are in seconds.
export const PROBLEM_TEXT = 'WHO estimated that anemia affected 1.62 billion people globally—nearly 1 in 4 individuals—in its 1993–2005 assessment. Hemoglobin testing traditionally uses a blood sample.';

export const config = {
  video: {id: 'IronScanIntro', width: 1920, height: 1080, fps: 30},
  colors: {
    teal: '#145247', marigold: '#FAA805', blue: '#CDE0E4', sand: '#E8D9C9',
    cream: '#FBF6EF', white: '#FFFFFF', glass: '#FFFFFF70', muted: '#58756D',
    border: '#FFFFFFB3', shadow: '#14524724', privacySurface: '#DEE0D8',
  },
  type: {serif: 'Fraunces', sans: 'DM Sans', hero: 184, title: 100, body: 34, small: 22},
  timing: {
    scenes: {opening: 4, problem: 4, process: 6, showcase: 12.2, closing: 3},
    transition: 0.4, screenshot: 2.2, screenshotSlide: 0.3,
    ribbon: 2.2, titleDelay: 0.65, taglineDelay: 1.25,
    wordStagger: 0.045, wordReveal: 0.28, cardStagger: 0.5,
    flowDelay: 2.1, aiDelay: 2.7, closingReveal: 0.35,
    taglineReveal: 0.83, wordStart: 0.27, noteDelay: 2.17, noteReveal: 0.67,
    cardStart: 0.53, flowReveal: 1, captionReveal: 0.3, ribbonEchoDelay: 0.33,
  },
  copy: {
    name: 'IronScan', eyebrow: 'CONGRESSIONAL APP CHALLENGE', tutorial: 'APP TUTORIAL',
    tagline: "Non-invasive hemoglobin & anemia screening, powered by on-device AI.",
    problemEyebrow: 'WHY IT MATTERS', problem: PROBLEM_TEXT,
    problemNote: 'Sources: WHO, Worldwide prevalence of anaemia 1993–2005; WHO Anaemia fact sheet — 40% of children aged 6–59 months and 30% of women aged 15–49 are affected.',
    problemIsPlaceholder: PROBLEM_TEXT.startsWith('['),
    processEyebrow: 'THREE VIEWS. ONE ESTIMATE.', processHeading: 'How it works',
    steps: [
      {title: '1. Conjunctiva', detail: 'Lower eyelid', icon: 'eye'},
      {title: '2. Fingernail Bed', detail: 'Fingertip', icon: 'nail'},
      {title: '3. Tongue', detail: 'Tongue surface', icon: 'tongue'},
    ],
    ai: 'On-device AI', aiDetail: 'Estimated hemoglobin', aiRisk: '+ risk level',
    aiFootnote: 'Images analyzed on your phone',
    techStack: 'Sigmoid-normalized CoreML fusion · Built with Swift, SwiftUI, Vision & AVFoundation',
    sampleNotice: 'Fictional sample data · non-clinical research prototype',
    showcaseEyebrow: 'DESIGNED TO GUIDE YOU', showcaseHeading: 'Meet your\nIronScan.',
    showcaseDetail: 'A guided scan. A clearer view.',
    screens: [
      {file: 'home.png', caption: 'Your dashboard', short: 'Home'},
      {file: 'scan.png', caption: 'Guided 3-step scan', short: 'Scan'},
      {file: 'history.png', caption: 'Track trends over time', short: 'History'},
      {file: 'learn.png', caption: 'Learn about iron health', short: 'Learn'},
      {file: 'profile.png', caption: 'Your profile', short: 'Profile'},
    ],
    closing: "Let's see IronScan in action.",
    disclaimer: 'Non-clinical research prototype. Does not replace laboratory testing.',
    prototype: 'NON-CLINICAL RESEARCH PROTOTYPE',
    placeholder: 'SCREENSHOT PLACEHOLDER', placeholderDetail: 'Add your app screenshot',
    demoGreeting: 'Hello, explorer', demoProfile: 'Demo profile', hiddenValue: '—',
  },
  assets: {screenshots: 'screenshots/', login: 'login.png', logo: 'logo.png', useLogo: false, maskPersonalDetails: false},
  output: {video: 'out/ironscan-intro.mp4', stills: 'out/stills', reviewFrames: [75,205,365,450,525,600,675,750,840]},
} as const;

export const frames = (seconds: number) => Math.round(seconds * config.video.fps);
export const sceneFrames = Object.fromEntries(
  Object.entries(config.timing.scenes).map(([key, seconds]) => [key, frames(seconds)]),
) as Record<keyof typeof config.timing.scenes, number>;
export const totalFrames = Object.values(sceneFrames).reduce((a, b) => a + b, 0);
