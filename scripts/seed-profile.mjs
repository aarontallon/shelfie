#!/usr/bin/env node
// ════════════════════════════════════════════════════════════════════════
// Shelfie — one-off profile seeding script
//
// Run this on YOUR OWN machine (not here) — it needs to reach your real
// Supabase project and Open Library over the internet, and it signs in with
// YOUR email/password, which never leaves your computer.
//
// What it does, in order:
//   1. Signs in as you.
//   2. For every book in your shelfie that has no cover yet, searches Open
//      Library for that title/author and sets a cover image.
//   3. Deletes ALL of your existing posts.
//   4. Publishes one fully-filled-out example post of each type the composer
//      supports (Publicación, Historia, Cita, Marginalia, Shelfie), using
//      real books from your own shelfie. The Cita is marked as spoiler.
//
// Usage:
//   npm install
//   SHELFIE_EMAIL="tu@email.com" SHELFIE_PASSWORD="tu-contraseña" node scripts/seed-profile.mjs
//
// (If you don't want the password in your shell history, just run the
// script without the env vars — it will ask for them interactively.)
// ════════════════════════════════════════════════════════════════════════

import { createClient } from '@supabase/supabase-js';
import readline from 'node:readline/promises';

const SUPA_URL = 'https://zkoarvxhjunwmyiaynyc.supabase.co';
const SUPA_KEY = 'sb_publishable_EkLevW97vxNd1UTKf3SLcw_FyT0S-iU';

const ENTER_CODES = [13, 10];
const CTRL_C_CODE = 3;
const BACKSPACE_CODES = [127, 8];

async function ask(prompt) {
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  const answer = await rl.question(prompt);
  rl.close();
  return answer.trim();
}

// Minimal masked input for the password prompt, using byte codes rather than
// literal control characters in source (which don't always survive intact).
async function askHidden(prompt) {
  return new Promise((resolve) => {
    process.stdout.write(prompt);
    const stdin = process.stdin;
    stdin.resume();
    stdin.setRawMode?.(true);
    let value = '';
    const onData = (buf) => {
      const code = buf[0];
      if (ENTER_CODES.includes(code)) {
        stdin.setRawMode?.(false);
        stdin.pause();
        stdin.removeListener('data', onData);
        process.stdout.write('\n');
        resolve(value.trim());
      } else if (code === CTRL_C_CODE) {
        process.exit(1);
      } else if (BACKSPACE_CODES.includes(code)) {
        value = value.slice(0, -1);
      } else {
        value += buf.toString('utf8');
      }
    };
    stdin.on('data', onData);
  });
}

async function findCover(title, author) {
  const q = `${title} ${author || ''}`.trim();
  const url = `https://openlibrary.org/search.json?q=${encodeURIComponent(q)}&limit=5&fields=title,author_name,cover_i,first_publish_year,edition_count`;
  const res = await fetch(url);
  if (!res.ok) return null;
  const data = await res.json();
  const docs = (data.docs || []).filter((d) => d.cover_i);
  if (!docs.length) return null;
  // "Latest edition" is approximated here: Open Library's search returns one
  // representative cover per work, not a full edition list per book (fetching
  // and ranking every edition for every book would mean 2 extra API calls per
  // book). We prefer the doc with the most editions — a good proxy for "the
  // edition most people actually have/see" — which is usually a recent,
  // widely-printed one.
  docs.sort((a, b) => (b.edition_count || 0) - (a.edition_count || 0));
  return `https://covers.openlibrary.org/b/id/${docs[0].cover_i}-L.jpg`;
}

async function main() {
  const email = process.env.SHELFIE_EMAIL || (await ask('Email de tu cuenta Shelfie: '));
  const password = process.env.SHELFIE_PASSWORD || (await askHidden('Contraseña: '));

  const supa = createClient(SUPA_URL, SUPA_KEY);
  console.log('Iniciando sesión...');
  const { data: authData, error: authErr } = await supa.auth.signInWithPassword({ email, password });
  if (authErr || !authData?.user) {
    console.error('No se pudo iniciar sesión:', authErr?.message || 'usuario no encontrado');
    process.exit(1);
  }
  const userId = authData.user.id;
  console.log(`Sesión iniciada (${email})`);

  // ---- 1. Covers ----
  const { data: books, error: booksErr } = await supa
    .from('user_books')
    .select('id,title,author,cover')
    .eq('user_id', userId);
  if (booksErr) { console.error('No se pudieron leer tus libros:', booksErr.message); process.exit(1); }

  const missing = (books || []).filter((b) => !b.cover);
  console.log(`\n${books.length} libros en tu shelfie, ${missing.length} sin portada. Buscando en Open Library...`);
  let updated = 0, notFound = 0;
  for (const book of missing) {
    try {
      const cover = await findCover(book.title, book.author);
      if (cover) {
        const { error } = await supa.from('user_books').update({ cover }).eq('id', book.id);
        if (error) throw error;
        updated++;
        console.log(`  OK  ${book.title} - ${book.author}`);
      } else {
        notFound++;
        console.log(`  --  Sin resultado: ${book.title} - ${book.author}`);
      }
    } catch (e) {
      notFound++;
      console.log(`  --  Error con "${book.title}": ${e.message}`);
    }
    await new Promise((r) => setTimeout(r, 300)); // be polite to Open Library
  }
  console.log(`\nPortadas actualizadas: ${updated}. Sin resultado: ${notFound}.`);

  // ---- 2. Delete all existing posts ----
  console.log('\nBorrando tus publicaciones actuales...');
  const { error: delErr } = await supa.from('posts').delete().eq('user_id', userId);
  if (delErr) { console.error('No se pudieron borrar las publicaciones:', delErr.message); process.exit(1); }
  console.log('Publicaciones borradas.');

  // ---- 3. Publish one complete example of each post type ----
  const { data: leidos } = await supa
    .from('user_books')
    .select('id,title,author,cover,color,stars')
    .eq('user_id', userId)
    .eq('status', 'leidos')
    .order('stars', { ascending: false })
    .limit(6);

  const pool = leidos && leidos.length ? leidos : (books || []).slice(0, 6);
  if (!pool.length) {
    console.log('\nNo tienes libros en "Leídos" para usar de ejemplo en las publicaciones -- se omite ese paso.');
  } else {
    const pick = (i) => pool[i % pool.length];
    const now = Date.now();
    const rows = [];

    // Publicación (tweet) -- reseña completa
    const b1 = pick(0);
    rows.push({
      user_id: userId,
      type: 'tweet',
      text: `Acabo de terminar «${b1.title}» y todavía estoy procesándolo. La construcción de personajes es de lo mejor que he leído este año, y el ritmo narrativo te atrapa desde el primer capítulo. Totalmente recomendado si te gusta la narrativa con capas.`,
      book_title: b1.title, book_author: b1.author, book_cover: b1.cover, book_color: b1.color,
      rating: b1.stars || 5,
      spoiler: false,
      extra: { title: `Por qué «${b1.title}» merece la pena`, isReview: true, page: '', chapter: '' },
    });

    // Historia (hilo) -- con personaje y varias partes
    const b2 = pick(1);
    rows.push({
      user_id: userId,
      type: 'hilo',
      text: 'Un hilo sobre el arco del protagonista y por qué su evolución me parece tan lograda (sin destripar el final).',
      book_title: b2.title, book_author: b2.author, book_cover: b2.cover, book_color: b2.color,
      rating: 0,
      spoiler: false,
      extra: {
        title: `El arco de personaje en «${b2.title}»`,
        page: '12', chapter: '3',
        character: b2.title.split(' ')[0],
        thread: [
          { text: 'Empieza como alguien completamente pasivo, casi una víctima de las circunstancias.', character: '' },
          { text: 'A mitad de libro toma su primera decisión propia, y ahí cambia todo el tono de la novela.', character: '' },
          { text: 'El desenlace lo cierra de una forma que solo funciona porque el autor sembró cada paso antes.', character: '' },
        ],
      },
    });

    // Cita -- marcada como spoiler
    const b3 = pick(2);
    rows.push({
      user_id: userId,
      type: 'cita',
      text: '',
      book_title: b3.title, book_author: b3.author, book_cover: b3.cover, book_color: b3.color,
      rating: 0,
      spoiler: true,
      extra: {
        title: '', page: '287', chapter: '19',
        quote: 'Nunca pensó que ese sería el último momento en que todos estarían juntos, y sin embargo, mirando atrás, era el único que de verdad importaba.',
      },
    });

    // Marginalia -- cita + anotaciones propias
    const b4 = pick(3);
    rows.push({
      user_id: userId,
      type: 'marginalia',
      text: '',
      book_title: b4.title, book_author: b4.author, book_cover: b4.cover, book_color: b4.color,
      rating: 0,
      spoiler: false,
      extra: {
        title: 'Anotación al margen',
        page: '54', chapter: '4',
        quote: 'El silencio, a veces, dice más que cualquier discurso que hayamos ensayado.',
        note: 'Subrayé esto la primera vez que lo leí y lo he vuelto a subrayar en la relectura -- es el tipo de frase que cambia de significado según el momento de tu vida en que la leas.',
      },
    });

    // Shelfie -- varios libros a la vez
    const shelfBooks = pool.slice(0, Math.min(5, pool.length)).map((b) => ({
      id: b.id, title: b.title, author: b.author, cover: b.cover, color: b.color,
    }));
    rows.push({
      user_id: userId,
      type: 'shelfiepost',
      text: 'Así va mi shelfie este mes -- mezcla de relecturas y descubrimientos nuevos.',
      book_title: null, book_author: null, book_cover: null, book_color: null,
      rating: 0,
      spoiler: false,
      extra: { title: '', shelfBooks, shelfViewMode: 'shelf' },
    });

    const { error: insErr } = await supa.from('posts').insert(rows);
    if (insErr) { console.error('No se pudieron publicar los posts de ejemplo:', insErr.message); process.exit(1); }
    console.log(`\nPublicadas ${rows.length} publicaciones de ejemplo (una por tipo, la Cita marcada como spoiler).`);
  }

  console.log('\nListo. Recarga la app para ver los cambios.');
}

main().catch((e) => { console.error('Error inesperado:', e); process.exit(1); });
