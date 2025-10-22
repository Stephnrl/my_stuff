import requests
import json
from datetime import datetime

# Configuration
GITHUB_TOKEN = "your-github-token-here"
GITHUB_REPO = "owner/repo-name"  # e.g., "actions/checkout"

def fetch_github_data(repo):
    """Fetch data from GitHub API using current best practices"""
    headers = {
        "Accept": "application/vnd.github+json",
        "Authorization": f"Bearer {GITHUB_TOKEN}",
        "X-GitHub-Api-Version": "2022-11-28"
    }
    base_url = f"https://api.github.com/repos/{repo}"
    
    print(f"Fetching data for {repo}...\n")
    
    data = {}
    
    try:
        # Repository info
        print("📦 Fetching repository info...")
        repo_info = requests.get(base_url, headers=headers)
        repo_info.raise_for_status()
        data['repo'] = repo_info.json()
        
        # Open issues
        print("🐛 Fetching open issues...")
        open_issues = requests.get(
            f"{base_url}/issues?state=open&per_page=100",
            headers=headers
        )
        open_issues.raise_for_status()
        data['open_issues'] = open_issues.json()
        
        # Closed issues (last 30)
        print("✅ Fetching closed issues...")
        closed_issues = requests.get(
            f"{base_url}/issues?state=closed&per_page=30",
            headers=headers
        )
        closed_issues.raise_for_status()
        data['closed_issues'] = closed_issues.json()
        
        # Pull requests
        print("🔀 Fetching pull requests...")
        prs = requests.get(
            f"{base_url}/pulls?state=all&per_page=30",
            headers=headers
        )
        prs.raise_for_status()
        data['prs'] = prs.json()
        
        # Releases
        print("🚀 Fetching releases...")
        releases = requests.get(
            f"{base_url}/releases",
            headers=headers
        )
        releases.raise_for_status()
        data['releases'] = releases.json()
        
        print("✓ All data fetched successfully!\n")
        return data
        
    except requests.exceptions.RequestException as e:
        print(f"❌ Error fetching data: {e}")
        if hasattr(e.response, 'text'):
            print(f"Response: {e.response.text}")
        return None

def print_summary(data):
    """Print a nice summary of the data"""
    if not data:
        return
    
    repo = data['repo']
    
    print("=" * 80)
    print(f"📊 REPOSITORY SUMMARY: {repo['full_name']}")
    print("=" * 80)
    print(f"Description: {repo.get('description', 'N/A')}")
    print(f"Stars: ⭐ {repo['stargazers_count']}")
    print(f"Forks: 🍴 {repo['forks_count']}")
    print(f"Open Issues: 🐛 {repo['open_issues_count']}")
    print(f"Language: {repo.get('language', 'N/A')}")
    print(f"Last Updated: {repo['updated_at']}")
    print()
    
    # Open Issues Summary
    print("-" * 80)
    print(f"🐛 OPEN ISSUES ({len(data['open_issues'])})")
    print("-" * 80)
    for issue in data['open_issues'][:10]:
        if 'pull_request' not in issue:  # Filter out PRs
            created = issue['created_at'][:10]
            print(f"  #{issue['number']}: {issue['title']}")
            print(f"    👤 {issue['user']['login']} | 📅 {created} | 💬 {issue['comments']} comments")
            if issue.get('labels'):
                labels = ', '.join([l['name'] for l in issue['labels']])
                print(f"    🏷️  {labels}")
            print()
    
    # Recent Closed Issues
    print("-" * 80)
    print(f"✅ RECENTLY CLOSED ISSUES (showing last 10)")
    print("-" * 80)
    for issue in data['closed_issues'][:10]:
        if 'pull_request' not in issue:
            closed = issue['closed_at'][:10] if issue.get('closed_at') else 'N/A'
            print(f"  #{issue['number']}: {issue['title']}")
            print(f"    👤 {issue['user']['login']} | 🔒 Closed: {closed}")
            print()
    
    # Pull Requests
    print("-" * 80)
    print(f"🔀 PULL REQUESTS (showing last 10)")
    print("-" * 80)
    for pr in data['prs'][:10]:
        status = "✅ MERGED" if pr.get('merged_at') else f"📝 {pr['state'].upper()}"
        created = pr['created_at'][:10]
        print(f"  {status} - #{pr['number']}: {pr['title']}")
        print(f"    👤 {pr['user']['login']} | 📅 {created}")
        if pr.get('merged_at'):
            print(f"    ✅ Merged: {pr['merged_at'][:10]}")
        print()
    
    # Releases
    print("-" * 80)
    print(f"🚀 RELEASES ({len(data['releases'])})")
    print("-" * 80)
    for release in data['releases'][:10]:
        published = release['published_at'][:10] if release.get('published_at') else 'N/A'
        prerelease = " (pre-release)" if release['prerelease'] else ""
        print(f"  📦 {release['tag_name']}: {release['name']}{prerelease}")
        print(f"    📅 Published: {published}")
        print(f"    ⬇️  Downloads: {sum([asset['download_count'] for asset in release.get('assets', [])])}")
        print()

def save_to_json(data, filename="github_data.json"):
    """Save raw data to JSON file for inspection"""
    if data:
        with open(filename, 'w') as f:
            json.dump(data, f, indent=2)
        print(f"\n💾 Raw data saved to {filename}")

def main():
    print("🚀 GitHub Data Fetcher\n")
    
    # Fetch data
    data = fetch_github_data(GITHUB_REPO)
    
    if data:
        # Print summary
        print_summary(data)
        
        # Save raw data
        save_to_json(data)
        
        # Print some stats
        print("\n" + "=" * 80)
        print("📈 QUICK STATS")
        print("=" * 80)
        actual_open_issues = len([i for i in data['open_issues'] if 'pull_request' not in i])
        actual_open_prs = len([p for p in data['prs'] if p['state'] == 'open'])
        merged_prs = len([p for p in data['prs'] if p.get('merged_at')])
        
        print(f"Open Issues (excluding PRs): {actual_open_issues}")
        print(f"Open Pull Requests: {actual_open_prs}")
        print(f"Merged PRs (last 30): {merged_prs}")
        print(f"Total Releases: {len(data['releases'])}")
        print()

if __name__ == "__main__":
    main()
