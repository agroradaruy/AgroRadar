export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') return res.status(200).end();

  // Fuentes RSS agropecuarias — todas públicas y gratuitas
  const FEEDS = [
    // Uruguay
    { url: 'https://www.uruguayxxi.gub.uy/es/rss/', label: 'Uruguay XXI', rubro: 'uruguay' },
    { url: 'https://www.mgap.gub.uy/rss.xml', label: 'MGAP', rubro: 'uruguay' },
    { url: 'https://www.elobservador.com.uy/rss/economia', label: 'El Observador', rubro: 'uruguay' },
    { url: 'https://www.elpais.com.uy/rss/economia.xml', label: 'El País', rubro: 'uruguay' },
    { url: 'https://www.lr21.com.uy/rss/economia.xml', label: 'LR21', rubro: 'uruguay' },
    // Internacional
    { url: 'https://www.contextoganadero.com/rss.xml', label: 'Contexto Ganadero', rubro: 'internacional' },
    { url: 'https://www.infocampo.com.ar/feed/', label: 'Infocampo', rubro: 'regional' },
    { url: 'https://www.agrofy.com.ar/feed', label: 'Agrofy', rubro: 'regional' },
    { url: 'https://www.ruminant.com.au/feed/', label: 'Ruminant', rubro: 'internacional' },
  ];

  const KEYWORDS = {
    ganadero: ['ganad', 'novillo', 'vacuno', 'bovino', 'ternero', 'faena', 'frigorif', 'carne', 'inac', 'acg', 'reposic'],
    internacional: ['live cattle', 'feeder', 'cbot', 'chicago', 'maiz', 'maíz', 'soja', 'trigo', 'commodity'],
    lacteo: ['leche', 'lácteo', 'lacteo', 'gdt', 'fonterra', 'tambo', 'inale', 'wmp'],
    politica: ['mgap', 'ministerio', 'ley', 'decreto', 'senado', 'diputados', 'agropecuar', 'política'],
    clima: ['lluvia', 'sequia', 'sequía', 'clima', 'temperatura', 'cosecha', 'siembra', 'precipit'],
    regional: ['brasil', 'argentina', 'real brasileño', 'mercosur', 'exportac'],
  };

  function detectRubro(title, desc) {
    const text = (title + ' ' + desc).toLowerCase();
    for (const [rubro, words] of Object.entries(KEYWORDS)) {
      if (words.some(w => text.includes(w))) return rubro;
    }
    return 'general';
  }

  async function parseFeed(feed) {
    try {
      const resp = await fetch(feed.url, {
        headers: { 'User-Agent': 'AgroRadar/1.0' },
        signal: AbortSignal.timeout(5000)
      });
      if (!resp.ok) return [];
      const xml = await resp.text();

      // Parse items from RSS
      const items = [];
      const itemRegex = /<item[^>]*>([\s\S]*?)<\/item>/gi;
      let match;

      while ((match = itemRegex.exec(xml)) !== null && items.length < 5) {
        const item = match[1];
        const title = (/<title[^>]*><!\[CDATA\[(.*?)\]\]><\/title>/i.exec(item) ||
                       /<title[^>]*>(.*?)<\/title>/i.exec(item))?.[1]?.trim() || '';
        const link = (/<link[^>]*>(.*?)<\/link>/i.exec(item) ||
                      /<link[^>]*href="(.*?)"/i.exec(item))?.[1]?.trim() || '';
        const desc = (/<description[^>]*><!\[CDATA\[(.*?)\]\]><\/description>/i.exec(item) ||
                      /<description[^>]*>(.*?)<\/description>/i.exec(item))?.[1]
                      ?.replace(/<[^>]+>/g, '')?.trim()?.slice(0, 200) || '';
        const pubDate = (/<pubDate[^>]*>(.*?)<\/pubDate>/i.exec(item))?.[1]?.trim() || '';

        if (title && link) {
          items.push({
            titulo: title.replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>'),
            link,
            resumen: desc.replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>'),
            fecha: pubDate ? new Date(pubDate).toLocaleDateString('es-UY') : '',
            fuente: feed.label,
            rubro: detectRubro(title, desc)
          });
        }
      }
      return items;
    } catch (e) {
      return [];
    }
  }

  try {
    const results = await Promise.allSettled(FEEDS.map(f => parseFeed(f)));
    const noticias = results
      .filter(r => r.status === 'fulfilled')
      .flatMap(r => r.value)
      .sort((a, b) => new Date(b.fecha) - new Date(a.fecha))
      .slice(0, 40);

    res.setHeader('Cache-Control', 's-maxage=1800'); // cache 30 min
    return res.status(200).json({ noticias, total: noticias.length, actualizado: new Date().toISOString() });

  } catch (e) {
    return res.status(500).json({ error: e.message });
  }
}
