# CI/CD Pipeline Documentation

## Overview

This CI/CD pipeline automatically builds and pushes Docker images whenever you push code to the `main` or `master` branch.

## What the Pipeline Does

1. **Gets New Code**: Automatically checks out the latest code from your repository
2. **Deletes Old Images**: Removes existing Docker images to ensure clean builds
3. **Builds Fresh Images**: Creates new Docker images with `--no-cache` for completely fresh builds
4. **Pushes to Registry**: Uploads images to GitHub Container Registry (ghcr.io)

## When It Runs

- ✅ **On Push**: Automatically triggers when you push code to `main` or `master` branch
- ✅ **Manual Trigger**: You can also manually trigger it from the GitHub Actions tab
- ❌ **Ignores**: Markdown file changes (`.md` files) won't trigger the pipeline

## Image Locations

After the pipeline runs, your images will be available at:

- **Backend**: `ghcr.io/YOUR_USERNAME/YOUR_REPO/asi-backend:latest`
- **Frontend**: `ghcr.io/YOUR_USERNAME/YOUR_REPO/asi-frontend:latest`

## Using the Images

### Pull Images Locally

```bash
# Login to GitHub Container Registry
echo $GITHUB_TOKEN | docker login ghcr.io -u YOUR_USERNAME --password-stdin

# Pull images
docker pull ghcr.io/YOUR_USERNAME/YOUR_REPO/asi-backend:latest
docker pull ghcr.io/YOUR_USERNAME/YOUR_REPO/asi-frontend:latest
```

### Update Kubernetes Deployments

Update your `k8s/backend-deployment.yaml` and `k8s/frontend-deployment.yaml`:

```yaml
image: ghcr.io/YOUR_USERNAME/YOUR_REPO/asi-backend:latest
imagePullPolicy: Always  # Always pull latest image
```

### Use in docker-compose.yml

```yaml
services:
  backend:
    image: ghcr.io/YOUR_USERNAME/YOUR_REPO/asi-backend:latest
    # ... rest of config
  
  frontend:
    image: ghcr.io/YOUR_USERNAME/YOUR_REPO/asi-frontend:latest
    # ... rest of config
```

## Image Visibility

By default, images in GitHub Container Registry are **private**. To make them public:

1. Go to your repository on GitHub
2. Click on "Packages" (right sidebar)
3. Click on the package (e.g., `asi-backend`)
4. Click "Package settings"
5. Scroll down to "Danger Zone"
6. Click "Change visibility" → "Make public"

## Pipeline Steps Breakdown

1. **Checkout Code**: Gets the latest code from your branch
2. **Setup Docker Buildx**: Prepares Docker for building
3. **Login to Registry**: Authenticates with GitHub Container Registry
4. **Cleanup Old Images**: Removes old Docker images to free space
5. **Build Backend**: Creates fresh backend Docker image (no cache)
6. **Build Frontend**: Creates fresh frontend Docker image (no cache)
7. **Push Images**: Uploads both images to the registry

## Troubleshooting

### Pipeline Not Running?

- Make sure you're pushing to `main` or `master` branch
- Check that you're not only changing `.md` files (these are ignored)
- Verify the workflow file is in `.github/workflows/` directory

### Build Failures?

- Check the Actions tab for detailed error messages
- Ensure your Dockerfiles are correct
- Verify all dependencies are properly specified

### Can't Pull Images?

- Make sure you're logged in to GitHub Container Registry
- Check image visibility settings (private vs public)
- Verify you have the correct image name and tag

## Customization

To modify the pipeline behavior, edit `.github/workflows/ci-cd.yml`:

- **Change trigger branches**: Modify the `on.push.branches` section
- **Use different registry**: Update the `REGISTRY` environment variable
- **Enable caching**: Change `no-cache: true` to `no-cache: false` and add cache settings
- **Add deployment step**: Add a new job to deploy to Kubernetes after building
