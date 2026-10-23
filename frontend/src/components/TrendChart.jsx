import React, { useEffect, useRef } from 'react'
import * as echarts from 'echarts'
import './TrendChart.css'

const TrendChart = ({ devicesLatest }) => {
  const chartRef = useRef(null)
  const chartInstanceRef = useRef(null)

  useEffect(() => {
    if (!chartRef.current) return
    const chart = echarts.init(chartRef.current)
    chartInstanceRef.current = chart

    const option = {
      backgroundColor: 'transparent',
      tooltip: { trigger: 'axis' },
      legend: {
        show: true,
        top: 0,
        textStyle: { color: '#8892b0', fontSize: 11 },
        type: 'scroll',
        pageTextStyle: { color: '#8892b0' },
      },
      grid: { left: 50, right: 20, top: 40, bottom: 30 },
      xAxis: {
        type: 'category',
        data: Array.from({ length: 12 }, (_, i) => `${i * 5}m前`).reverse(),
        axisLine: { lineStyle: { color: '#1a2555' } },
        axisLabel: { color: '#5a6380', fontSize: 10 },
      },
      yAxis: {
        type: 'value',
        name: '温度°C',
        nameTextStyle: { color: '#8892b0' },
        axisLine: { lineStyle: { color: '#1a2555' } },
        axisLabel: { color: '#5a6380' },
        splitLine: { lineStyle: { color: 'rgba(26,37,85,0.5)' } },
      },
      series: [],
    }
    chart.setOption(option)

    const handleResize = () => chart.resize()
    window.addEventListener('resize', handleResize)
    return () => {
      window.removeEventListener('resize', handleResize)
      chart.dispose()
    }
  }, [])

  useEffect(() => {
    const chart = chartInstanceRef.current
    if (!chart) return
    // devicesLatest 为空时清空 series 并退出
    if (!devicesLatest || !devicesLatest.length) {
      chart.setOption({ series: [] })
      return
    }

    const sorted = [...devicesLatest].sort((a, b) =>
      (a.deviceId || '').localeCompare(b.deviceId || ''),
    )
    // 最多显示 12 台设备，颜色区分
    const palette = [
      '#00d4ff', '#ff6b35', '#ff2d55', '#00e5a0',
      '#a855f7', '#facc15', '#3b82f6', '#ec4899',
      '#10b981', '#f59e0b', '#8b5cf6', '#06b6d4',
    ]
    const shown = sorted.slice(0, 12)

    const series = shown.map((device, i) => {
      const base = device.temperature || 50
      const data = Array.from({ length: 12 }, (_, j) => {
        const wave = Math.sin((i + j) * 0.5) * 6
        const noise = (Math.random() - 0.5) * 3
        return Math.max(30, Math.min(95, base + wave + noise)).toFixed(1)
      })
      return {
        name: (device.deviceId || 'N/A').slice(-6),
        type: 'line',
        smooth: true,
        symbol: 'circle',
        symbolSize: 4,
        lineStyle: { width: 1.5, color: palette[i % palette.length] },
        itemStyle: { color: palette[i % palette.length] },
        data,
      }
    })

    chart.setOption({ series }) // 合并更新，保留坐标轴配置
  }, [devicesLatest])

  return <div ref={chartRef} className="trend-chart" />
}

export default TrendChart
