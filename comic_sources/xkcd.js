// Uses the official public JSON interface: https://xkcd.com/json.html
class Xkcd extends ComicSource {
    name = "xkcd"
    key = "xkcd"
    version = "1.0.0"
    minAppVersion = "1.6.0"
    url = "https://raw.githubusercontent.com/ltt2077/venera/glass-cloud/comic_sources/xkcd.js"

    cache = new Map()
    latestAt = 0
    latest = null

    async getComic(id) {
        if (id !== null && this.cache.has(id)) return this.cache.get(id)
        if (id === null && this.latest && Date.now() - this.latestAt < 60000) return this.latest
        const path = id === null ? "" : `${id}/`
        const res = await Network.get(`https://xkcd.com/${path}info.0.json`)
        if (res.status !== 200) throw `xkcd: HTTP ${res.status}`
        const item = JSON.parse(res.body)
        if (!Number.isInteger(item.num) || typeof item.img !== "string" ||
            !item.img.startsWith("https://imgs.xkcd.com/")) throw "Invalid xkcd response"
        if (this.cache.size >= 32) this.cache.delete(this.cache.keys().next().value)
        this.cache.set(item.num, item)
        if (id === null) {
            this.latest = item
            this.latestAt = Date.now()
        }
        return item
    }

    thumbnail(item) {
        return {
            id: String(item.num),
            title: item.safe_title || item.title,
            subtitle: `#${item.num} · ${item.year}-${item.month}-${item.day}`,
            cover: item.img,
            description: item.alt || "",
        }
    }

    explore = [{
        title: "xkcd",
        type: "multiPageComicList",
        load: async (page) => {
            const latest = await this.getComic(null)
            // Number 404 deliberately does not exist. Rank the remaining comics.
            const total = latest.num >= 404 ? latest.num - 1 : latest.num
            const start = total - (page - 1) * 4
            const ranks = Array.from({ length: Math.max(0, Math.min(4, start)) }, (_, i) => start - i)
            const items = await Promise.all(ranks.map(rank => this.getComic(rank >= 404 ? rank + 1 : rank)))
            return { comics: items.map(item => this.thumbnail(item)), maxPage: Math.ceil(total / 4) }
        },
    }]

    // The official interface has no full-text search; search by comic number.
    search = {
        load: async (keyword, options, page) => {
            const value = keyword.trim()
            if (page !== 1 || !/^\d+$/.test(value)) return { comics: [], maxPage: 1 }
            const id = Number(value)
            const latest = await this.getComic(null)
            if (id < 1 || id === 404 || id > latest.num) return { comics: [], maxPage: 1 }
            return { comics: [this.thumbnail(await this.getComic(id))], maxPage: 1 }
        },
    }

    comic = {
        loadInfo: async (id) => {
            const item = await this.getComic(Number(id))
            return new ComicDetails({
                ...this.thumbnail(item),
                description: [item.alt, item.transcript].filter(Boolean).join("\n\n"),
                tags: { Author: ["Randall Munroe"], Language: ["English"] },
                url: `https://xkcd.com/${item.num}/`,
            })
        },
        loadEp: async (id, epId) => ({ images: [(await this.getComic(Number(id))).img] }),
    }
}
