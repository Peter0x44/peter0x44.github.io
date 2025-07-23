# File Descriptor Two

Peter0x44's technical musings - A minimal Hugo blog using the PaperMod theme.

## Quick Start

### Local Development Workflow
1. **Start development server** - Double-click `serve.bat` or run:
   ```bash
   hugo server
   ```
   Then open: http://localhost:1313
   
2. **Add a new post**:
   ```bash
   hugo new posts/my-new-post.md
   ```
   
3. **Test your changes** - The development server auto-reloads when you save files

4. **Push to deploy** - When you're happy with your changes:
   ```bash
   git add .
   git commit -m "Add new post"
   git push origin master
   ```

### Automatic Deployment
Your site automatically deploys to GitHub Pages when you push to the `master` branch using GitHub Actions.

**Setup (one-time):**
1. Go to your repository Settings → Pages
2. Set Source to "GitHub Actions"
3. The workflow will run automatically on each push to master

**Manual options:**
- Trigger deployment manually from the Actions tab
- Build locally with `hugo` then serve with `serve.py` for static testing

Your live site: https://peter0x44.github.io/

## File Structure
- `content/posts/` - Your blog posts (Markdown files)
- `config.toml` - Site configuration
- `public/` - Generated static site (after running `hugo`)
- `themes/PaperMod/` - The theme files

## Writing Posts
Create new `.md` files in `content/posts/` with this format:
```markdown
---
title: "My Post Title"
date: 2025-07-22T12:00:00Z
draft: false
---

Your content here in Markdown...
```

## Commands to Remember

### Development
- `hugo server` - Start development server with live reload
- `hugo server --bind=0.0.0.0` - Start server accessible from network
- `hugo new posts/filename.md` - Create new post

### Building & Testing
- `hugo` - Build static site (creates `public/` folder)
- `hugo --minify` - Build optimized for production
- `serve.bat` - Quick start development server (Windows)
- `serve.py` - Serve built site locally for testing

### Deployment
- `git push origin master` - Trigger automatic deployment to GitHub Pages
- Manual deployment available from GitHub Actions tab
