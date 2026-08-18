import { useState, useCallback, useRef } from 'react'
import { useRemake, useFeatures, useGoAchv, useGoThanks } from '@remake/hooks'
import { useProfileInject, useUniqueInject } from '@remake/hooks'
import { TextSvg } from '@/components/TextSvg'
import ThemeToggle from '@/components/ThemeToggle'
import Github from '@/components/Github'
import Modal from '@/components/Modal'
import { encrypt, decrypt } from '@/crypto'
import { get, set } from '@/storage'
import './Home.css'

function ExportModal({ open, onClose }: { open: boolean; onClose: () => void }) {
    const [password, setPassword] = useState('')
    const [token, setToken] = useState('')
    const [msg, setMsg] = useState('')
    const [msgType, setMsgType] = useState<'success' | 'error'>('success')
    const [busy, setBusy] = useState(false)

    const showMsg = (text: string, type: 'success' | 'error') => {
        setMsg(text)
        setMsgType(type)
    }

    const handleExport = useCallback(async () => {
        if (!password) {
            showMsg('请输入密码', 'error')
            return
        }
        setBusy(true)
        setMsg('')
        try {
            const profile = await get('profile')
            const unique = await get('unique')
            const data = JSON.stringify({ profile, unique })
            const encrypted = await encrypt(data, password)
            setToken(encrypted)
            showMsg('加密成功！请复制下方字符串妥善保存', 'success')
        } catch {
            showMsg('导出失败', 'error')
        }
        setBusy(false)
    }, [password])

    const handleCopy = useCallback(async () => {
        try {
            await navigator.clipboard.writeText(token)
            showMsg('已复制到剪贴板', 'success')
        } catch {
            showMsg('复制失败，请手动复制', 'error')
        }
    }, [token])

    const handleDownload = useCallback(() => {
        const blob = new Blob([token], { type: 'text/plain' })
        const url = URL.createObjectURL(blob)
        const a = document.createElement('a')
        a.href = url
        a.download = `liferestart-save-${Date.now()}.txt`
        a.click()
        URL.revokeObjectURL(url)
        showMsg('已下载', 'success')
    }, [token])

    const handleClose = useCallback(() => {
        setPassword('')
        setToken('')
        setMsg('')
        onClose()
    }, [onClose])

    return (
        <Modal open={open} title="导出存档" onClose={handleClose}>
            <label>
                <span>设置密码（用于加密）</span>
                <input
                    type="password"
                    value={password}
                    onChange={e => setPassword(e.target.value)}
                    placeholder="请输入密码"
                />
            </label>
            <button
                className="primary"
                onClick={handleExport}
                disabled={busy}
            >
                {busy ? '加密中...' : '生成加密存档'}
            </button>
            {token && (
                <>
                    <label>
                        <span>加密存档（请妥善保存）</span>
                        <textarea
                            value={token}
                            readOnly
                            rows={4}
                            onClick={e =>
                                (e.target as HTMLTextAreaElement).select()
                            }
                        />
                    </label>
                    <div className="modal-actions">
                        <button onClick={handleCopy}>复制到剪贴板</button>
                        <button onClick={handleDownload}>下载为文件</button>
                    </div>
                </>
            )}
            {msg && <div className={`modal-msg ${msgType}`}>{msg}</div>}
        </Modal>
    )
}

function ImportModal({
    open,
    onClose,
}: {
    open: boolean
    onClose: () => void
}) {
    const [password, setPassword] = useState('')
    const [token, setToken] = useState('')
    const [msg, setMsg] = useState('')
    const [msgType, setMsgType] = useState<'success' | 'error'>('success')
    const [busy, setBusy] = useState(false)
    const fileRef = useRef<HTMLInputElement>(null)
    const profileInject = useProfileInject()
    const uniqueInject = useUniqueInject()

    const showMsg = (text: string, type: 'success' | 'error') => {
        setMsg(text)
        setMsgType(type)
    }

    const handleImport = useCallback(async () => {
        if (!password) {
            showMsg('请输入密码', 'error')
            return
        }
        if (!token) {
            showMsg('请输入加密字符串或选择文件', 'error')
            return
        }
        setBusy(true)
        setMsg('')
        try {
            const data = await decrypt(token, password)
            const { profile, unique } = JSON.parse(data)
            await set('profile', profile)
            if (unique) await set('unique', unique)
            // Update in-memory state
            const parsed = JSON.parse(profile)
            profileInject({
                ...parsed,
                times: parsed.times || 0,
                achievements: new Set(parsed.achievements || []),
                events: new Set(parsed.events || []),
                talents: new Set(parsed.talents || []),
            })
            if (unique) uniqueInject(JSON.parse(unique))
            showMsg('导入成功！存档已恢复', 'success')
        } catch {
            showMsg('导入失败，请检查密码或存档字符串', 'error')
        }
        setBusy(false)
    }, [password, token, profileInject, uniqueInject])

    const handleFile = useCallback(
        (e: React.ChangeEvent<HTMLInputElement>) => {
            const file = e.target.files?.[0]
            if (!file) return
            const reader = new FileReader()
            reader.onload = () => {
                setToken(reader.result as string)
                showMsg('文件已加载，请输入密码后点击导入', 'success')
            }
            reader.readAsText(file)
        },
        [showMsg],
    )

    const handleClose = useCallback(() => {
        setPassword('')
        setToken('')
        setMsg('')
        if (fileRef.current) fileRef.current.value = ''
        onClose()
    }, [onClose])

    return (
        <Modal open={open} title="导入存档" onClose={handleClose}>
            <label>
                <span>输入密码（解密用）</span>
                <input
                    type="password"
                    value={password}
                    onChange={e => setPassword(e.target.value)}
                    placeholder="请输入密码"
                />
            </label>
            <label>
                <span>粘贴加密字符串</span>
                <textarea
                    value={token}
                    onChange={e => setToken(e.target.value)}
                    placeholder="粘贴加密存档字符串..."
                    rows={4}
                />
            </label>
            <div>
                <span style={{ fontSize: '0.9rem', color: 'var(--base-text-color)', userSelect: 'none' }}>
                    或从文件导入
                </span>
                <input
                    ref={fileRef}
                    type="file"
                    accept=".txt"
                    onChange={handleFile}
                    style={{ marginTop: '0.25rem' }}
                />
            </div>
            <button
                className="primary"
                onClick={handleImport}
                disabled={busy}
            >
                {busy ? '导入中...' : '导入存档'}
            </button>
            {msg && <div className={`modal-msg ${msgType}`}>{msg}</div>}
        </Modal>
    )
}

export default function Home() {
    const remake = useRemake()
    const features = useFeatures()
    const goAchv = useGoAchv()
    const goThanks = useGoThanks()
    const [exportOpen, setExportOpen] = useState(false)
    const [importOpen, setImportOpen] = useState(false)

    return (
        <div className="screen home">
            <div className="title">
                <TextSvg text="人生重开模拟器" className="main" />
                <TextSvg text="这垃圾人生一秒也不想待了" className="sub" />
            </div>
            <div className="controls">
                <div>
                    <button className="primary focus" onClick={remake}>
                        立即重开
                    </button>
                </div>
                {features && (
                    <div>
                        <button className="secondary" onClick={goAchv}>
                            成就
                        </button>
                        <button className="secondary" onClick={goThanks}>
                            感谢
                        </button>
                    </div>
                )}
                <div>
                    <button
                        className="secondary"
                        onClick={() => setExportOpen(true)}
                    >
                        导出
                    </button>
                    <button
                        className="secondary"
                        onClick={() => setImportOpen(true)}
                    >
                        导入
                    </button>
                </div>
            </div>
            <div className="actions">
                {features && <Github />}
                <ThemeToggle />
            </div>
            <ExportModal open={exportOpen} onClose={() => setExportOpen(false)} />
            <ImportModal open={importOpen} onClose={() => setImportOpen(false)} />
        </div>
    )
}
