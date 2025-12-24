# GitHub Actions CI/CD Pipeline

This directory contains GitHub Actions workflows for building and pushing Docker images for the ASI Dashboard application.

## Workflows

### 1. `ci-cd.yml` - Main CI/CD Pipeline

This is the primary workflow that runs on every push and pull request.

**Triggers:**
- Push to `main` branch
- Pull requests to `main` branch
- Tags starting with `v*`

**Jobs:**
1. **backend-test**: Tests and builds the backend TypeScript code
2. **frontend-test**: Tests and builds the Flutter frontend
3. **build-and-push**: Builds Docker images and pushes to GitHub Container Registry (ghcr.io)

### 2. `docker-build.yml` - Manual Docker Build

Allows manual building of Docker images with custom options.

**Triggers:**
- Manual workflow dispatch (Actions tab → Run workflow)
- Push to main branch when backend/frontend files change

**Options:**
- **Component**: Choose to build `backend`, `frontend`, or `both`
- **Tag**: Custom tag for the image (defaults to `latest`)
- **Push**: Whether to push to registry (default: true)

## Setup Instructions

### 1. Container Registry

The workflows use GitHub Container Registry (ghcr.io) by default. Images will be available at:
- `ghcr.io/YOUR_USERNAME/YOUR_REPO/asi-backend:latest`
- `ghcr.io/YOUR_USERNAME/YOUR_REPO/asi-frontend:latest`

**No additional setup needed** - GitHub Actions automatically authenticates using `GITHUB_TOKEN`.

### 2. Using Docker Images

After the workflow runs, you can pull and use the images:

```bash
# Pull images
docker pull ghcr.io/YOUR_USERNAME/YOUR_REPO/asi-backend:latest
docker pull ghcr.io/YOUR_USERNAME/YOUR_REPO/asi-frontend:latest

# Run with docker-compose
# Update docker-compose.yml to use the registry images:
#   image: ghcr.io/YOUR_USERNAME/YOUR_REPO/asi-backend:latest
#   image: ghcr.io/YOUR_USERNAME/YOUR_REPO/asi-frontend:latest
```

### 3. Image Visibility

By default, images in GitHub Container Registry are private. To make them public:
1. Go to your repository on GitHub
2. Click on "Packages" (right sidebar)
3. Click on the package (asi-backend or asi-frontend)
4. Go to "Package settings"
5. Scroll down and click "Change visibility" → "Make public"

## Usage

### Automatic Build and Push

1. Push to `main` branch
2. Workflow automatically:
   - Tests code
   - Builds Docker images
   - Pushes to registry

### Manual Build

1. Go to Actions tab
2. Select "Docker Build and Push"
3. Click "Run workflow"
4. Choose options:
   - Component: backend, frontend, or both
   - Tag: custom tag (optional)
   - Push: whether to push to registry
5. Click "Run workflow"

## Customization

### Change Container Registry

To use Docker Hub or another registry, update the `REGISTRY` environment variable in the workflows:

```yaml
env:
  REGISTRY: docker.io  # or your-registry.com
```

And update login step in both workflows:
```yaml
- name: Log in to Container Registry
  uses: docker/login-action@v3
  with:
    registry: ${{ env.REGISTRY }}
    username: ${{ secrets.DOCKER_USERNAME }}
    password: ${{ secrets.DOCKER_PASSWORD }}
```

Then add these secrets in GitHub:
- `DOCKER_USERNAME`: Your Docker Hub username
- `DOCKER_PASSWORD`: Your Docker Hub password or access token

### Change Image Names

Update the image name variables:
```yaml
env:
  BACKEND_IMAGE_NAME: your-org/asi-backend
  FRONTEND_IMAGE_NAME: your-org/asi-frontend
```

## Troubleshooting

### Build Failures

- Check that Dockerfiles are correct
- Verify all dependencies are listed in package.json/pubspec.yaml
- Check build logs for specific errors
- Ensure Dockerfile paths are correct in workflow

### Push Failures

- Ensure repository has proper permissions
- Check that GITHUB_TOKEN has write access to packages
- If using Docker Hub, verify DOCKER_USERNAME and DOCKER_PASSWORD secrets are set
- Check registry authentication in workflow logs

### Image Pull Errors

If you can't pull images:
1. Make repository/package public in GitHub, or
2. Authenticate with GitHub Container Registry:
   ```bash
   echo $GITHUB_TOKEN | docker login ghcr.io -u USERNAME --password-stdin
   ```
3. For Docker Hub, use: `docker login`

## Security Best Practices

1. **Secrets**: Never commit secrets to the repository
2. **Image Scanning**: Enable GitHub's Dependabot for vulnerability scanning
3. **Tag Strategy**: Use specific tags (not just `latest`) for production
4. **Branch Protection**: Protect main branch
5. **Image Visibility**: Keep images private unless they need to be public

## Support

For issues or questions:
1. Check workflow logs in the Actions tab
2. Check container registry for pushed images
3. Verify Docker images locally: `docker pull ghcr.io/YOUR_USERNAME/YOUR_REPO/asi-backend:latest`
4. Test Docker images: `docker run -p 3000:3000 ghcr.io/YOUR_USERNAME/YOUR_REPO/asi-backend:latest`

