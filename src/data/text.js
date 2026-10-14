// Player-facing writing that no item, npc or quest owns, from data/text.json.
// (Quest and objective text lives in data/quests.json.)

import { DB } from './db.js';

export const INTRO = DB.text.intro;
export const EXAMINE = DB.text.examine;
export const DOCUMENTS = Object.fromEntries(Object.entries(DB.text.documents).map(([id, d]) => [id, { title: d.title, body: d.body.join('') }]));
