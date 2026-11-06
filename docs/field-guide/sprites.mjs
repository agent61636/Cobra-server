// Shared pixel sprites for the field guide. All original drawings.
// One character per pixel; "." is transparent. Colours come from PALETTE (or data-pal on the <pre>).
// Use in a page:  <pre class="sprite" data-name="viper" data-px="5"></pre>
// Or draw one inline:  <pre class="sprite" data-px="4" data-pal="Q:#ff00ff">..KK..\n.KQQK.</pre>

export const PALETTE = {
  K: "#111014", // ink
  W: "#ffffff",
  R: "#e4202a",
  B: "#1d3fbb",
  Y: "#ffd400",
  G: "#18a548",
  L: "#9be22d",
  P: "#6b2fa0",
  O: "#ff7a00",
  S: "#00a6e0",
  N: "#ff4fa3",
  T: "#5d6b7a", // steel
  D: "#3a3640", // dark grey
  E: "#c9c4cf", // light grey
  C: "#f1c08a", // skin
  M: "#8a5a2b", // brown
  F: "#4cff7a", // phosphor green
};

export const SPRITES = {
  // Claude-Viper, our host: a hooded cobra in Cobra blue
  viper: `
.......KKKKKK.......
......KBBBBBBK......
.....KBRRRRRRBK.....
.....KBRWRRWRBK.....
....KBBBBBBBBBBK....
...KBBBBBKKBBBBBK...
..KBBYYBBBBBBYYBBK..
.KBBYKKYBBBBYKKYBBK.
.KBBYKKYBBBBYKKYBBK.
.KBBBYYBBBBBBYYBBBK.
..KBBBBBBYYBBBBBBK..
...KBBBBYYYYBBBBK...
....KBBBBYYBBBBK....
.....KBBBBBBBBK.....
......KBBBBBBK......
.......KBBBBK.......
......KBBBBK........
.....KBBBBK..KKKK...
....KBBBBKKKKBBBBK..
...KBBBBBBBBBBBBBBK.
....KKKKKKKKKKKKKK..`,

  // a sneaky Joe (generic green-helmet saboteur) for the trap pages
  joe: `
.....KKKKKK.....
....KGGGGGGK....
...KGGGGGGGGK...
..KKKKKKKKKKKK..
...KCCCCCCCCK...
...KCKCCCCKCK...
...KCCCCCCCCK...
...KCCKKKKCCK...
....KCCCCCCK....
.....KKKKKK.....
...KGGGGGGGGK...
..KGGGGGGGGGGK..
..KGGKGGGGKGGK..
..KGGKGGGGKGGK..
..KKKKGGGGKKKK..
.....KKKKKK.....`,

  star: `
.....KK.....
....KYYK....
....KYYK....
KKKKKYYKKKKK
KYYYYYYYYYYK
.KYYYYYYYYK.
..KYYYYYYK..
..KYYKKYYK..
.KYYK..KYYK.
.KKK....KKK.`,

  heart: `
.KK...KK.
KRRK.KRRK
KRWRKRRRK
KRRRRRRRK
.KRRRRRK.
..KRRRK..
...KRK...
....K....`,

  coin: `
..KKKK..
.KYYYYK.
KYYWYYOK
KYWYYYOK
KYYYYYOK
KYYYYYOK
.KYYOOK.
..KKKK..`,

  lock: `
...KKKK...
..KEEEEK..
.KEK..KEK.
.KEK..KEK.
KKKKKKKKKK
KYYYYYYYYK
KYYYKKYYYK
KYYYKKYYYK
KYYYYYYYYK
KKKKKKKKKK`,

  key: `
.KKK.........
KYYYK........
KYKYKKKKKKKKK
KYYYYYYYYYYYK
KYKYKKKKKYKYK
KYYYK....K.K.
.KKK.........`,

  floppy: `
KKKKKKKKKKK.
KBBEEEEEBBK.
KBBEEEKEBBBK
KBBEEEKEBBBK
KBBBBBBBBBBK
KBWWWWWWWWBK
KBWKKKKKKWBK
KBWWWWWWWWBK
KBWKKKKKKWBK
KKKKKKKKKKKK`,

  server: `
KKKKKKKKKKKK
KTTTTTTTTTTK
KTFTFTKKKKTK
KTTTTTTTTTTK
KKKKKKKKKKKK
KTTTTTTTTTTK
KTFTRTKKKKTK
KTTTTTTTTTTK
KKKKKKKKKKKK
KTTTTTTTTTTK
KTFTFTKKKKTK
KTTTTTTTTTTK
KKKKKKKKKKKK
.KK......KK.`,

  skull: `
..KKKKKK..
.KWWWWWWK.
KWWWWWWWWK
KWKKWWKKWK
KWKKWWKKWK
KWWWKKWWWK
.KWWWWWWK.
..KWKWKWK.
..KKKKKKK.`,

  pod: `
....KKKKKKKK....
..KKSSSSSSSSKK..
.KSSWWSSSSSSSSK.
KSSWWSSSSSSSSSSK
KSSSSSSSSSSSSSSK
KSSKKKKKKKKKKSSK
KSSKFKFKFKFKKSSK
KSSKKKKKKKKKKSSK
KSSSSSSSSSSSSSSK
.KSSSSSSSSSSSSK.
..KKSSSSSSSSKK..
....KKKKKKKK....`,
};
