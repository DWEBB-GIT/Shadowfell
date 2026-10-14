// Player-facing writing. Kept apart from code so it can be revised freely.

export const DOCUMENTS = {
  manifest: {
    title: 'Carriage Manifest',
    body: [
      '<p class="doc-head">HOLLIN &amp; DAUGHTERS, CARTERS<br>Fallen Road toll, third day of Thawmonth</p>',
      '<p><b>Consignment:</b> grave-iron, <s>twelve</s> <i>nine</i> bars, bearing the mark of Venn\'s forge.</p>',
      '<p><b>For:</b> the quartermaster at the old watch post, Ashford Rise.</p>',
      '<p><b>Driver:</b> <span class="scratched">&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</span> &mdash; scored out hard enough to tear the paper.</p>',
      '<p><b>Also carried:</b> six bells, small, for the chapel.</p>',
      '<p class="doc-margin">Along the margin, in a different hand:<br>&ldquo;Not the bells. Whatever he tells you, the bells do not go into the ground at Hallow Cut. Bring them back with the iron.&rdquo;</p>',
    ].join(''),
  },
};

export const EXAMINE = {
  cart:
    'A merchant cart, dragged off the road and abandoned. One wheel is gone and the chest in the bed has been forced. Whoever did it was not interested in the iron.',
  waymarker:
    'An old road marker. The distance to the watch post has been chiselled away, and someone has scratched a small bell beneath it.',
  hallow_cut:
    'Timber grave markers, newer than anything else on this road. A small bell hangs from each. The earth around them has been turned recently.',
  watch_post:
    'The door of the watch post is barred from the outside. Nobody has come or gone in some time.',
  blackwood_edge:
    'A standing stone at the edge of the pines, older than the road. A rune on its face gives off a cold green light, and fresh claw marks score its base.',
  hound_den:
    'Gnawed bones, some of them still in boots. The barrow hounds den here, and they do not like visitors.',
  archer_camp:
    'A smashed crate stamped with the watch tower. Arrows, no bowstrings, and a cold fire. The archers here stopped needing to eat some time ago.',
  seer_stones:
    'A ring of stones lit with witchlight. Grave-iron bars have been driven into the earth at its heart, nine of them, in a circle. So this is where Mara\'s iron went.',
  shrine_first:
    'The candles are fresh and someone has left bread in the bowl this morning. Whoever keeps this shrine is not far away.',
};

export const OBJECTIVE = {
  title: 'The Missing Delivery',
  stages: {
    start: 'Mara Venn\'s iron never reached the old watch post. Follow the Fallen Road and look for some sign of it.',
    cartFound: 'A merchant cart lies off the road, missing a wheel. Search it for anything that explains what happened.',
    complete: 'You have the manifest. Grave-iron bound for the watch post, a scratched-out name, and a warning about bells. Take it to Mara Venn at her forge by the watch post.',
    reported: 'Mara has the manifest and paid you for it. The carters turned off north, into the Blackwood.',
  },
};

// What Mara Venn says, by how far the delivery story has got.
export const MARA = {
  start: 'Iron\'s late, and the watch post won\'t answer its door. Nine bars of grave-iron with my mark on them went up that road. Find out what happened and I\'ll pay for it. Need kit in the meantime? I\'ve some.',
  cartFound: 'A cart off the road? Then someone stopped it. Look it over properly. A carter keeps papers.',
  complete: 'That\'s Hollin\'s hand, and my mark on the iron. You found the manifest?',
  handIn: 'Hand over the manifest',
  thanks: 'Bells at Hallow Cut. I don\'t like that at all. Here, as promised. If you mean to look further, look north, into the Blackwood. That\'s where the carters turn off.',
  done: 'Bells in the ground and a driver nobody will name. I\'ll be asking questions in the village. Meanwhile, my forge is open.',
};

export const INTRO =
  'You came up the Fallen Road for work, not glory. A blacksmith named Mara Venn will pay for word of a missing iron delivery. That is reason enough.';
