// Polyfill for legacy WebView2 (< Chromium 117), e.g. outdated Evergreen Runtime.
// Must be imported before any other module in the entry.

if (typeof Map.groupBy !== 'function') {
    Map.groupBy = <K, T>(
        items: Iterable<T>,
        key: (item: T, index: number) => K,
    ): Map<K, T[]> => {
        const map = new Map<K, T[]>()
        let index = 0
        for (const item of items) {
            const k = key(item, index++)
            const group = map.get(k)
            if (group) group.push(item)
            else map.set(k, [item])
        }
        return map
    }
}

if (typeof Object.groupBy !== 'function') {
    Object.groupBy = <K extends PropertyKey, T>(
        items: Iterable<T>,
        key: (item: T, index: number) => K,
    ): Partial<Record<K, T[]>> => {
        const obj = Object.create(null) as Partial<Record<K, T[]>>
        let index = 0
        for (const item of items) {
            const k = key(item, index++)
            const group = obj[k]
            if (group) group.push(item)
            else obj[k] = [item]
        }
        return obj
    }
}
