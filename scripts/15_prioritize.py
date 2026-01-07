#!/usr/bin/env python3
import json
import sys
import os

def calculate_score(asset):
    score = 0
    tags = []
    
    # 1. Keywords in URL/Host
    high_signal_keywords = ['admin', 'internal', 'staging', 'dev', 'api', 'vpn', 'jira', 'grafana', 'prometheus', 'jenkins', 'gitlab']
    url = asset.get('url', '').lower()
    host = asset.get('host', '').lower()
    
    for kw in high_signal_keywords:
        if kw in url or kw in host:
            score += 30
            tags.append(f"keyword:{kw}")
            break
            
    # 2. Status Codes
    status = asset.get('status_code', 0)
    if status == 403:
        score += 20
        tags.append("status:403")
    elif status == 401:
        score += 25
        tags.append("status:401")
    elif status == 500:
        score += 15
        tags.append("status:500")
    
    # 3. Technologies
    techs = asset.get('tech', [])
    high_risk_tech = ['jenkins', 'old-version', 'iis', 'php']
    for t in techs:
        if t.lower() in high_risk_tech:
            score += 20
            tags.append(f"tech:{t}")
            
    return score, tags

def main():
    if len(sys.argv) < 2:
        print("Usage: 15_prioritize.py <output_dir>")
        sys.exit(1)
        
    out_dir = sys.argv[1]
    httpx_file = os.path.join(out_dir, "httpx.json")
    output_file = os.path.join(out_dir, "prioritized_assets.json")
    
    if not os.path.exists(httpx_file):
        print(f"Error: {httpx_file} not found")
        sys.exit(1)
        
    results = []
    with open(httpx_file, 'r') as f:
        for line in f:
            if not line.strip(): continue
            try:
                asset = json.loads(line)
                score, tags = calculate_score(asset)
                asset['priority_score'] = score
                asset['priority_tags'] = tags
                results.append(asset)
            except Exception as e:
                pass

    results.sort(key=lambda x: x.get('priority_score', 0), reverse=True)
    with open(output_file, 'w') as f:
        json.dump(results, f, indent=2)
        
    print(f"✓ Prioritized {len(results)} assets.")

if __name__ == "__main__":
    main()
