Enterprise Git Coding Standards
Here are key Git coding standards commonly implemented at enterprise-level companies:
Branching Strategy

Git Flow or Trunk-Based Development: Most enterprises use either Git Flow (feature, develop, release, hotfix branches) or Trunk-Based Development (short-lived feature branches merged frequently to main)
Branch Naming Conventions: Use descriptive prefixes like feature/, bugfix/, hotfix/, release/ followed by ticket numbers and brief descriptions (e.g., feature/ABC-123-user-authentication)

Commit Practices

Atomic Commits: Each commit should represent a single logical change
Descriptive Commit Messages: Follow formats like "type(scope): subject" (e.g., "fix(auth): resolve token validation issue")
Signed Commits: Many enterprises require commit signing with GPG keys for security verification

Code Review and Integration

Pull Request Templates: Standardized templates with checklists for testing, documentation, and security considerations
Required Reviews: Minimum of 1-2 approvals before merging code
CI/CD Integration: Automated tests must pass before code can be merged

Tools and Environment

Approved Editor: VSCode (as you mentioned)
Approved Extensions: Often enterprises maintain a list of approved/vetted VSCode extensions
Disallowed Tools: Random editors not approved by IT (as you mentioned)
Git Hooks: Pre-commit and pre-push hooks for linting, formatting, and security scanning

Security and Compliance

Secrets Management: No credentials, tokens, or secrets in code repositories
Regular Audits: Scan repositories for sensitive information
Access Control: Role-based permissions for repository access

Documentation

README Standards: All repositories include standardized README files
CONTRIBUTING Guidelines: Clear instructions for contributing code
Architecture Documentation: System design documents maintained alongside code

Would you like me to elaborate on any specific aspect of these standards?
