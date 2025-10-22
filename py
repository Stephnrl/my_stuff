import requests
import json
from datetime import datetime

# Configuration
GITHUB_TOKEN = "your-github-token-here"
CONFLUENCE_TOKEN = "your-confluence-token-here"
CONFLUENCE_BASE_URL = "https://your-confluence.com"  # No trailing slash
PAGE_ID = "296172954"  # Your page ID
GITHUB_REPO = "owner/repo-name"

def fetch_github_data(repo):
    """Fetch data from GitHub API"""
    headers = {
        "Accept": "application/vnd.github+json",
        "Authorization": f"Bearer {GITHUB_TOKEN}",
        "X-GitHub-Api-Version": "2022-11-28"
    }
    base_url = f"https://api.github.com/repos/{repo}"
    
    print(f"📡 Fetching data for {repo}...\n")
    
    data = {}
    
    try:
        # Repository info
        print("  📦 Repository info...")
        repo_info = requests.get(base_url, headers=headers)
        repo_info.raise_for_status()
        data['repo'] = repo_info.json()
        
        # Open issues
        print("  🐛 Open issues...")
        open_issues = requests.get(
            f"{base_url}/issues?state=open&per_page=100",
            headers=headers
        )
        open_issues.raise_for_status()
        data['open_issues'] = open_issues.json()
        
        # Closed issues
        print("  ✅ Closed issues...")
        closed_issues = requests.get(
            f"{base_url}/issues?state=closed&per_page=30",
            headers=headers
        )
        closed_issues.raise_for_status()
        data['closed_issues'] = closed_issues.json()
        
        # Pull requests
        print("  🔀 Pull requests...")
        prs = requests.get(
            f"{base_url}/pulls?state=all&per_page=30",
            headers=headers
        )
        prs.raise_for_status()
        data['prs'] = prs.json()
        
        # Releases
        print("  🚀 Releases...")
        releases = requests.get(
            f"{base_url}/releases",
            headers=headers
        )
        releases.raise_for_status()
        data['releases'] = releases.json()
        
        print("✓ GitHub data fetched successfully!\n")
        return data
        
    except requests.exceptions.RequestException as e:
        print(f"❌ Error fetching GitHub data: {e}")
        return None

def create_confluence_html(data, repo_name):
    """Generate Confluence storage format HTML"""
    repo = data['repo']
    
    # Filter out PRs from issues
    open_issues_only = [i for i in data['open_issues'] if 'pull_request' not in i]
    closed_issues_only = [i for i in data['closed_issues'] if 'pull_request' not in i]
    open_prs = [p for p in data['prs'] if p['state'] == 'open']
    merged_prs = [p for p in data['prs'] if p.get('merged_at')]
    
    html = f"""
<h1>GitHub Action: {repo['name']}</h1>
<p><em>Last updated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S UTC')}</em></p>

<h2>📊 Repository Overview</h2>
<table>
    <tbody>
        <tr>
            <th>Repository</th>
            <td><a href="{repo['html_url']}">{repo['full_name']}</a></td>
        </tr>
        <tr>
            <th>Description</th>
            <td>{repo.get('description', 'N/A')}</td>
        </tr>
        <tr>
            <th>Language</th>
            <td>{repo.get('language', 'N/A')}</td>
        </tr>
        <tr>
            <th>Stars</th>
            <td>⭐ {repo['stargazers_count']}</td>
        </tr>
        <tr>
            <th>Forks</th>
            <td>🍴 {repo['forks_count']}</td>
        </tr>
        <tr>
            <th>Last Updated</th>
            <td>{repo['updated_at'][:10]}</td>
        </tr>
    </tbody>
</table>

<h2>📈 Current Statistics</h2>
<table>
    <tbody>
        <tr>
            <th>Metric</th>
            <th>Count</th>
        </tr>
        <tr>
            <td>Open Issues</td>
            <td>{len(open_issues_only)}</td>
        </tr>
        <tr>
            <td>Open Pull Requests</td>
            <td>{len(open_prs)}</td>
        </tr>
        <tr>
            <td>Recently Closed Issues</td>
            <td>{len(closed_issues_only)}</td>
        </tr>
        <tr>
            <td>Recently Merged PRs</td>
            <td>{len(merged_prs)}</td>
        </tr>
        <tr>
            <td>Total Releases</td>
            <td>{len(data['releases'])}</td>
        </tr>
    </tbody>
</table>

<h2>🐛 Open Issues ({len(open_issues_only)})</h2>
"""
    
    if open_issues_only:
        html += "<ul>"
        for issue in open_issues_only[:15]:
            labels = ', '.join([f"<strong>{l['name']}</strong>" for l in issue.get('labels', [])])
            html += f"""
        <li>
            <a href="{issue['html_url']}">#{issue['number']}: {issue['title']}</a>
            <br/>
            👤 {issue['user']['login']} | 📅 {issue['created_at'][:10]} | 💬 {issue['comments']} comments
            {f"<br/>🏷️ {labels}" if labels else ""}
        </li>"""
        html += "</ul>"
    else:
        html += "<p>No open issues! 🎉</p>"
    
    html += f"""
<h2>✅ Recently Closed Issues ({len(closed_issues_only)})</h2>
"""
    
    if closed_issues_only:
        html += "<ul>"
        for issue in closed_issues_only[:10]:
            html += f"""
        <li>
            <a href="{issue['html_url']}">#{issue['number']}: {issue['title']}</a>
            <br/>
            👤 {issue['user']['login']} | 🔒 Closed: {issue['closed_at'][:10] if issue.get('closed_at') else 'N/A'}
        </li>"""
        html += "</ul>"
    else:
        html += "<p>No recently closed issues.</p>"
    
    html += f"""
<h2>🔀 Recent Pull Requests</h2>
<h3>Open PRs ({len(open_prs)})</h3>
"""
    
    if open_prs:
        html += "<ul>"
        for pr in open_prs[:10]:
            html += f"""
        <li>
            <a href="{pr['html_url']}">#{pr['number']}: {pr['title']}</a>
            <br/>
            👤 {pr['user']['login']} | 📅 {pr['created_at'][:10]}
        </li>"""
        html += "</ul>"
    else:
        html += "<p>No open pull requests.</p>"
    
    html += f"""
<h3>Recently Merged PRs ({len(merged_prs)})</h3>
"""
    
    if merged_prs:
        html += "<ul>"
        for pr in merged_prs[:10]:
            html += f"""
        <li>
            ✅ <a href="{pr['html_url']}">#{pr['number']}: {pr['title']}</a>
            <br/>
            👤 {pr['user']['login']} | ✅ Merged: {pr['merged_at'][:10]}
        </li>"""
        html += "</ul>"
    else:
        html += "<p>No recently merged pull requests.</p>"
    
    html += """
<h2>🚀 Latest Releases</h2>
"""
    
    if data['releases']:
        html += "<ul>"
        for release in data['releases'][:5]:
            prerelease = " <strong>(Pre-release)</strong>" if release['prerelease'] else ""
            downloads = sum([asset['download_count'] for asset in release.get('assets', [])])
            html += f"""
        <li>
            <a href="{release['html_url']}"><strong>{release['tag_name']}</strong>: {release['name']}</a>{prerelease}
            <br/>
            📅 Published: {release['published_at'][:10] if release.get('published_at') else 'N/A'} | ⬇️ Downloads: {downloads}
        </li>"""
        html += "</ul>"
    else:
        html += "<p>No releases yet.</p>"
    
    return html

def get_current_page(page_id):
    """Get current page data including version number"""
    headers = {
        "Authorization": f"Bearer {CONFLUENCE_TOKEN}",
        "Accept": "application/json"
    }
    
    print(f"📄 Getting current page data for ID {page_id}...")
    
    try:
        response = requests.get(
            f"{CONFLUENCE_BASE_URL}/rest/api/content/{page_id}",
            headers=headers
        )
        response.raise_for_status()
        page = response.json()
        print(f"✓ Current version: {page['version']['number']}\n")
        return page
    except requests.exceptions.RequestException as e:
        print(f"❌ Error getting page: {e}")
        if hasattr(e, 'response') and e.response is not None:
            print(f"Response: {e.response.text}")
        return None

def update_confluence_page(page_id, html_content):
    """Update Confluence page with new content"""
    headers = {
        "Authorization": f"Bearer {CONFLUENCE_TOKEN}",
        "Content-Type": "application/json"
    }
    
    # Get current page
    current_page = get_current_page(page_id)
    if not current_page:
        return None
    
    current_version = current_page['version']['number']
    new_version = current_version + 1
    
    print(f"📝 Updating page to version {new_version}...")
    
    # Prepare update payload
    update_data = {
        "id": page_id,
        "type": "page",
        "title": current_page['title'],  # Keep existing title
        "space": {"key": current_page['space']['key']},
        "version": {"number": new_version},
        "body": {
            "storage": {
                "value": html_content,
                "representation": "storage"
            }
        }
    }
    
    try:
        response = requests.put(
            f"{CONFLUENCE_BASE_URL}/rest/api/content/{page_id}",
            headers=headers,
            json=update_data
        )
        response.raise_for_status()
        result = response.json()
        print(f"✅ Page updated successfully!")
        print(f"🔗 View at: {CONFLUENCE_BASE_URL}{result['_links']['webui']}\n")
        return result
    except requests.exceptions.RequestException as e:
        print(f"❌ Error updating page: {e}")
        if hasattr(e, 'response') and e.response is not None:
            print(f"Response: {e.response.text}")
        return None

def main():
    print("=" * 80)
    print("🚀 GitHub to Confluence Sync")
    print("=" * 80)
    print()
    
    # Fetch GitHub data
    github_data = fetch_github_data(GITHUB_REPO)
    
    if not github_data:
        print("❌ Failed to fetch GitHub data. Exiting.")
        return
    
    # Generate Confluence HTML
    print("🎨 Generating Confluence content...")
    html_content = create_confluence_html(github_data, GITHUB_REPO)
    print("✓ Content generated!\n")
    
    # Update Confluence page
    result = update_confluence_page(PAGE_ID, html_content)
    
    if result:
        print("=" * 80)
        print("✅ SUCCESS!")
        print("=" * 80)
    else:
        print("=" * 80)
        print("❌ FAILED")
        print("=" * 80)

if __name__ == "__main__":
    main()
