export type SignalState = 'ACTIVE' | 'WATCHING' | 'PAPER_FILLED'

export interface SignalPreview {
  id: string
  state: SignalState
  label: 'BUY' | 'SELL' | 'NOTE'
  symbol: string
  detail: string
  timestamp: string
}

export const paperDashboardPreview: SignalPreview[] = [
  {
    id: 'watch-condition',
    state: 'WATCHING',
    label: 'NOTE',
    symbol: 'Awaiting data',
    detail: 'NOTE alerts will appear only when a time-bound action condition is detected.',
    timestamp: 'Data source not connected',
  },
  {
    id: 'paper-safety',
    state: 'ACTIVE',
    label: 'BUY',
    symbol: 'PAPER MODE',
    detail: 'Actionable BUY/SELL signals require fresh-price and risk revalidation before a virtual fill.',
    timestamp: 'Safety rule active',
  },
]
