export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  if (req.method === 'OPTIONS') return res.status(200).end();

  // Google News RSS — funciona desde servidores externos, completamente público
  const FEEDS = [
    { url: 'https://news.google.com/rss/search?q=ganaderia+uruguay&hl=es-419&gl=UY&ceid=UY:es-419', rubro: 'ganadero', label: 'Google News' },
    { url: 'https://news.google.com/rss/search?q=precio+novillo+uruguay+carne&hl=es-419&gl=UY&ceid=UY:es-419', rubro: 'ganadero', label: 'Google News' },
    { url: 'https://news.google.com/rss/search?q=exportacion+carne+uruguay&hl=es-419&gl=UY&ceid=UY:es-419', rubro: 'ganadero', label: 'Google News' },
    { url: 'https://news.google.com/rss/search?q=live+cattle+beef+price&hl=es-419&gl=UY&ceid=UY:es-419', rubro: 'internacional', label: 'Google News' },
    { url: 'https://news.google.com/rss/search?q=maiz+soja+chicago+precio&hl=es-419&gl=UY&ceid=UY:es-419', rubro: 'internacional', label: 'Google News' },
    { url: 'https://news.google.com/rss/search?q=leche+lacteos+uruguay+GDT&hl=es-419&gl=UY&ceid=UY:es-419', rubro: 'lacteo', label: 'Google News' },
    { url: 'https://news.google.com/rss/search?q=MGAP+agropecuario+uruguay&hl=es-419&gl=UY&ceid=UY:es-419', rubro: 'politica', label: 'Google News' },
    { url: 'https://news.google.com/rss/search?q=clima+lluvia+sequia+uruguay+agro&hl=es-419&gl=UY&ceid=UY:es-419', rubro: 'clima', label: 'Google News' },
    { url: 'https://news.google.com/rss/search?q=ganaderia+brasil+argentina+carne+exportacion&hl=es-419&gl=UY&ceid=UY:es-419', rubro: 'regional', label: 'Google News' },
  ];

  async function parseFeed(feed) {
    try {
      const resp = await fetch(feed.url, {
        headers: { 'User-Agent': 'Mozilla/5.0 (compatible; AgroRadar/1.0)' },
        signal: AbortSignal.timeout(6000)
      });
      if (!resp.ok) return [];
      const xml = await resp.text();

      const items = [];
      const itemRegex = /<item>([\s\S]*?)<\/item>/gi;
      let match;

      while ((match = itemRegex.exec(xml)) !== null && items.length < 6) {
        const item = match[1];

        const titleMatch = /<title><!\[CDATA\[(.*?)\]\]><\/title>/i.exec(item) ||
                           /<title>(.*?)<\/title>/i.exec(item);
        const linkMatch = /<link>(.*?)<\/link>/i.exec(item);
        const descMatch = /<description><!\[CDATA\[(.*?)\]\]><\/description>/i.exec(item) ||
                          /<description>(.*?)<\/description>/i.exec(item);
        const dateMatch = /<pubDate>(.*?)<\/pubDate>/i.exec(item);
        const sourceMatch = /<source[^>]*>(.*?)<\/source>/i.exec(item);

        const title = titleMatch?.[1]?.replace(/<[^>]+>/g, '')?.trim();
        const link = linkMatch?.[1]?.trim();
        if (!title || !link) continue;

        const desc = descMatch?.[1]
          ?.replace(/<[^>]+>/g, '')
          ?.replace(/&amp;/g, '&')
          ?.replace(/&lt;/g, '<')
          ?.replace(/&gt;/g, '>')
          ?.replace(/&#39;/g, "'")
          ?.trim()
          ?.slice(0, 220) || '';

        const fuente = sourceMatch?.[1]?.trim() || feed.label;
        const fecha = dateMatch?.[1] ? new Date(dateMatch[1]).toLocaleDateString('es-UY', { day:'2-digit', month:'short' }) : '';

        items.push({
          titulo: title.replace(/&amp;/g,'&').replace(/&#39;/g,"'").replace(/&quot;/g,'"'),
          link,
          resumen: desc,
          fecha,
          fuente,
          rubro: feed.rubro
        });
      }
      return items;
    } catch (e) {
      return [];
    }
  }

  try {
    const results = await Promise.allSettled(FEEDS.map(f => parseFeed(f)));
    const todas = results
      .filter(r => r.status === 'fulfilled')
      .flatMap(r => r.value);

    // Deduplicar por título similar
    const vistas = new Set();
    const noticias = todas.filter(n => {
      const key = n.titulo.slice(0, 60).toLowerCase();
      if (vistas.has(key)) return false;
      vistas.add(key);
      return true;
    }).slice(0, 50);

    res.setHeader('Cache-Control', 's-maxage=1800');
    return res.status(200).json({
      noticias,
      total: noticias.length,
      actualizado: new Date().toLocaleString('es-UY', { timeZone: 'America/Montevideo' })
    });

  } catch (e) {
    return res.status(500).json({ error: e.message });
  }
}
