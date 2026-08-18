import { useEffect, useRef, type ReactNode } from 'react'
import './Modal.css'

interface ModalProps {
    open: boolean
    title: string
    onClose: () => void
    children: ReactNode
}

export default function Modal({ open, title, onClose, children }: ModalProps) {
    const ref = useRef<HTMLDivElement>(null)

    useEffect(() => {
        if (!open) return
        const handler = (e: KeyboardEvent) => {
            if (e.key === 'Escape') onClose()
        }
        document.addEventListener('keydown', handler)
        return () => document.removeEventListener('keydown', handler)
    }, [open, onClose])

    if (!open) return null

    return (
        <div className="modal-overlay" onClick={onClose}>
            <div
                className="modal-content"
                ref={ref}
                onClick={e => e.stopPropagation()}
            >
                <div className="modal-header">
                    <span className="modal-title">{title}</span>
                    <button className="modal-close" onClick={onClose}>
                        ✕
                    </button>
                </div>
                <div className="modal-body">{children}</div>
            </div>
        </div>
    )
}
