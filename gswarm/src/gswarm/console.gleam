
pub fn html() -> String {
  "<!DOCTYPE html>
<html lang=\"en\">
<head>
    <meta charset=\"UTF-8\">
    <title>Sovereign Console | Gswarm</title>
    <script src=\"https://d3js.org/d3.v7.min.js\"></script>
    <link href=\"https://fonts.googleapis.com/css2?family=Outfit:wght@300;400;600;800&family=Inter:wght@400;600&display=swap\" rel=\"stylesheet\">
    <style>
        :root {
            --bg: #030712;
            --card-bg: rgba(17, 24, 39, 0.7);
            --border: rgba(255, 255, 255, 0.08);
            --gold: #f59e0b;
            --accent: #3b82f6;
        }
        body { 
            font-family: 'Inter', sans-serif; 
            background: var(--bg); 
            color: #f8fafc; 
            margin: 0; 
            overflow: hidden; 
        }
        #graph-container { 
            width: 100vw; 
            height: 100vh; 
            position: absolute; 
            top: 0; 
            left: 0; 
            z-index: 1; 
        }
        .overlay {
            position: absolute;
            z-index: 2;
            pointer-events: none;
            padding: 2rem;
            width: 100%;
            height: 100%;
            box-sizing: border-box;
            display: flex;
            flex-direction: column;
            justify-content: space-between;
        }
        header {
            display: flex;
            justify-content: space-between;
            align-items: flex-start;
        }
        h1 {
            font-family: 'Outfit', sans-serif;
            font-size: 2rem;
            margin: 0;
            background: linear-gradient(135deg, #fff 0%, #94a3b8 100%);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
        }
        .status-panel {
            background: var(--card-bg);
            backdrop-filter: blur(10px);
            border: 1px solid var(--border);
            padding: 1rem;
            border-radius: 0.5rem;
            pointer-events: auto;
            min-width: 200px;
        }
        .metric {
            display: flex;
            justify-content: space-between;
            margin-bottom: 0.5rem;
            font-size: 0.9rem;
        }
        .metric-label { color: #94a3b8; }
        .metric-value { font-weight: 600; color: #fff; }
        .metric-value.good { color: #10b981; }
        
        .leaderboard-panel {
            position: absolute;
            right: 2rem;
            top: 2rem;
            width: 300px;
            background: var(--card-bg);
            backdrop-filter: blur(10px);
            border: 1px solid var(--border);
            border-radius: 0.5rem;
            padding: 1rem;
            pointer-events: auto;
            max-height: 80vh;
            overflow-y: auto;
        }
        .lb-item {
            display: flex;
            justify-content: space-between;
            padding: 0.5rem 0;
            border-bottom: 1px solid rgba(255,255,255,0.05);
            font-size: 0.85rem;
        }
        .lb-rank { color: var(--gold); font-weight: bold; width: 20px; }
        .lb-name { color: #fff; flex-grow: 1; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; margin-right: 0.5rem; }
        .lb-score { color: #10b981; font-family: monospace; }
        
        /* D3 Styles */
        .node circle { stroke: #fff; stroke-width: 1.5px; }
        .link { stroke: #999; stroke-opacity: 0.6; }
        .link.mirror_link { stroke: #f59e0b; stroke-opacity: 0.8; stroke-dasharray: 5,5; }
        .label { font-size: 10px; fill: #ccc; pointer-events: none; }
    </style>
</head>
<body>
    <div id=\"graph-container\"></div>
    
    <div class=\"overlay\">
        <header>
            <div>
                <h1>Sovereign Console</h1>
                <div style=\"color: var(--gold); font-size: 0.8rem; letter-spacing: 0.1em; text-transform: uppercase;\">Gswarm v2.2.0</div>
            </div>
            <div class=\"status-panel\">
                <div class=\"metric\">
                    <span class=\"metric-label\">Status</span>
                    <span class=\"metric-value good\">● ACTIVE</span>
                </div>
                <div class=\"metric\">
                    <span class=\"metric-label\">Shards</span>
                    <span class=\"metric-value\" id=\"shard-count\">-</span>
                </div>
                <div class=\"metric\">
                    <span class=\"metric-label\">Memory</span>
                    <span class=\"metric-value\" id=\"memory-usage\">-</span>
                </div>
                <div class=\"metric\">
                    <span class=\"metric-label\">Uptime</span>
                    <span class=\"metric-value\" id=\"uptime\">-</span>
                </div>
            </div>
        </header>
        
        <div class=\"leaderboard-panel\">
            <h3 style=\"margin: 0 0 1rem 0; font-size: 1rem; color: #ccc;\">Top Alpha Generation</h3>
            <div id=\"lb-list\"></div>
        </div>
    </div>

    <script>
        // --- D3 Initialization ---
        const width = window.innerWidth;
        const height = window.innerHeight;
        
        const svg = d3.select(\"#graph-container\").append(\"svg\")
            .attr(\"width\", width)
            .attr(\"height\", height);
            
        const simulation = d3.forceSimulation()
            .force(\"link\", d3.forceLink().id(d => d.id).distance(100))
            .force(\"charge\", d3.forceManyBody().strength(-300))
            .force(\"center\", d3.forceCenter(width / 2, height / 2));
            
        // --- Data Fetching ---
        
        async function fetchData() {
            try {
                // Fetch Graph Data
                const graphRes = await fetch('/api/graph');
                const graphData = await graphRes.json();
                updateGraph(graphData);
                
                // Fetch Health
                const healthRes = await fetch('/api/health');
                const healthData = await healthRes.json();
                document.getElementById('shard-count').innerText = healthData.shard_count;
                document.getElementById('memory-usage').innerText = healthData.memory_mb + ' MB';
                document.getElementById('uptime').innerText = formatUptime(healthData.uptime_sec);
                
                // Fetch Leaderboard
                const lbRes = await fetch('/api/leaderboard');
                const lbData = await lbRes.json();
                updateLeaderboard(lbData);
                
            } catch (e) {
                console.error(\"Fetch error:\", e);
            }
        }
        
        function updateGraph(data) {
            // Check if simulation effectively changed
            // For now, basic enter/update logic
            
            const link = svg.selectAll(\".link\")
                .data(data.links)
                .join(\"line\")
                .attr(\"class\", d => d.type === 'mirror_link' ? 'link mirror_link' : 'link');

            const node = svg.selectAll(\".node\")
                .data(data.nodes)
                .join(\"g\")
                .attr(\"class\", \"node\")
                .call(d3.drag()
                    .on(\"start\", dragstarted)
                    .on(\"drag\", dragged)
                    .on(\"end\", dragended));
            
            node.selectAll(\"circle\").remove(); // Simple clear
            node.append(\"circle\")
                .attr(\"r\", d => {
                    if (d.type === 'shard') return 20;
                    if (d.type === 'mirror') return 25;
                    if (d.type === 'market') return 10;
                    return 5;
                })
                .attr(\"fill\", d => {
                    if (d.type === 'shard') return '#3b82f6';
                    if (d.type === 'mirror') return '#f59e0b';
                    if (d.type === 'market') return '#f59e0b';
                    const colors = {
                        'Institutional Insider': '#f43f5e',
                        'Reactive Momentum': '#3b82f6',
                        'Diversified Alpha': '#10b981',
                        'High-Frequency Noise': '#94a3b8',
                        'Passive Liquidity': '#6366f1'
                    };
                    return colors[d.cluster] || '#10b981';
                });
                
            node.selectAll(\"text\").remove();
            node.append(\"text\")
                .text(d => d.label)
                .attr(\"class\", \"label\")
                .attr(\"x\", 12)
                .attr(\"y\", 3);

            simulation.nodes(data.nodes).on(\"tick\", ticked);
            simulation.force(\"link\").links(data.links);
            simulation.alpha(0.3).restart();
            
            function ticked() {
                link
                    .attr(\"x1\", d => d.source.x)
                    .attr(\"y1\", d => d.source.y)
                    .attr(\"x2\", d => d.target.x)
                    .attr(\"y2\", d => d.target.y);

                node
                    .attr(\"transform\", d => `translate(${d.x},${d.y})`);
            }
        }
        
        function updateLeaderboard(data) {
            const list = document.getElementById('lb-list');
            list.innerHTML = '';
            data.traders.forEach((t, i) => {
                const div = document.createElement('div');
                div.className = 'lb-item';
                div.innerHTML = `
                    <span class=\"lb-rank\">${i+1}</span>
                    <span class=\"lb-name\">${t.id}</span>
                    <span class=\"lb-score\">${t.alpha.toFixed(2)}</span>
                `;
                list.appendChild(div);
            });
        }
        
        // --- Utils ---
        function formatUptime(sec) {
            const h = Math.floor(sec / 3600);
            const m = Math.floor((sec % 3600) / 60);
            return `${h}h ${m}m`;
        }
        
        function dragstarted(event, d) {
          if (!event.active) simulation.alphaTarget(0.3).restart();
          d.fx = d.x;
          d.fy = d.y;
        }

        function dragged(event, d) {
          d.fx = event.x;
          d.fy = event.y;
        }

        function dragended(event, d) {
          if (!event.active) simulation.alphaTarget(0);
          d.fx = null;
          d.fy = null;
        }
        
        // --- Init ---
        fetchData();
        setInterval(fetchData, 2000); // Poll every 2s
    </script>
</body>
</html>"
}
