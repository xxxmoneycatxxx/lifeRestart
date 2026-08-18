// AES-GCM encryption with PBKDF2 key derivation
// Compatible with Chromium 100+ (Web Crypto API)

const SALT_LEN = 16
const IV_LEN = 12
const KEY_LEN = 256
const ITERATIONS = 100000

async function deriveKey(password: string, salt: Uint8Array) {
    const enc = new TextEncoder()
    const keyMaterial = await crypto.subtle.importKey(
        'raw',
        enc.encode(password),
        'PBKDF2',
        false,
        ['deriveKey'],
    )
    return crypto.subtle.deriveKey(
        { name: 'PBKDF2', salt, iterations: ITERATIONS, hash: 'SHA-256' },
        keyMaterial,
        { name: 'AES-GCM', length: KEY_LEN },
        false,
        ['encrypt', 'decrypt'],
    )
}

function toBase64(bytes: Uint8Array) {
    let binary = ''
    for (const b of bytes) binary += String.fromCharCode(b)
    return btoa(binary)
}

function fromBase64(base64: string) {
    const binary = atob(base64)
    const bytes = new Uint8Array(binary.length)
    for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i)
    return bytes
}

export async function encrypt(plaintext: string, password: string) {
    const salt = crypto.getRandomValues(new Uint8Array(SALT_LEN))
    const iv = crypto.getRandomValues(new Uint8Array(IV_LEN))
    const key = await deriveKey(password, salt)
    const enc = new TextEncoder()
    const ciphertext = new Uint8Array(
        await crypto.subtle.encrypt(
            { name: 'AES-GCM', iv },
            key,
            enc.encode(plaintext),
        ),
    )
    // Format: base64(salt + iv + ciphertext)
    const combined = new Uint8Array(salt.length + iv.length + ciphertext.length)
    combined.set(salt, 0)
    combined.set(iv, salt.length)
    combined.set(ciphertext, salt.length + iv.length)
    return toBase64(combined)
}

export async function decrypt(token: string, password: string) {
    const combined = fromBase64(token.trim())
    const salt = combined.slice(0, SALT_LEN)
    const iv = combined.slice(SALT_LEN, SALT_LEN + IV_LEN)
    const ciphertext = combined.slice(SALT_LEN + IV_LEN)
    const key = await deriveKey(password, salt)
    const plaintext = new Uint8Array(
        await crypto.subtle.decrypt({ name: 'AES-GCM', iv }, key, ciphertext),
    )
    return new TextDecoder().decode(plaintext)
}
