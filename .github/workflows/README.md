# CI/CD Pipeline Documentation

## Overview

This CI/CD pipeline automatically builds Docker images **directly on your EC2 instance** whenever you push code to the `main` or `master` branch.

## What the Pipeline Does

1. **Gets New Code**: Pulls the latest code from your repository on EC2
2. **Deletes Old Images**: Removes existing Docker images on EC2 to ensure clean builds
3. **Builds Fresh Images**: Creates new Docker images directly on EC2 with `--no-cache` for completely fresh builds
4. **Restarts Containers**: Automatically restarts your application containers with the new images

## When It Runs

- ✅ **On Push**: Automatically triggers when you push code to `main` or `master` branch
- ✅ **Manual Trigger**: You can also manually trigger it from the GitHub Actions tab
- ❌ **Ignores**: Markdown file changes (`.md` files) won't trigger the pipeline

## Image Locations

After the pipeline runs, your images are built **directly on EC2**:

- **Backend**: `asi-backend:latest` (built on EC2)
- **Frontend**: `asi-frontend:latest` (built on EC2)

**No container registry needed!** Everything builds directly on your EC2 server.

## Setup Required

### GitHub Secrets

You need to configure these secrets in your GitHub repository:

1. Go to **Settings** → **Secrets and variables** → **Actions**
2. Add the following secrets:

| Secret Name | Description | Example |
|------------|-------------|---------|
| `EC2_SSH_KEY` | Your EC2 private SSH key (entire key including `-----BEGIN RSA PRIVATE KEY-----`) | `-----BEGIN RSA PRIVATE KEY-----...` |
| `EC2_HOST` | Your EC2 instance IP or hostname | `ec2-12-34-56-78.compute-1.amazonaws.com` or `12.34.56.78` |
| `EC2_USER` | SSH username for EC2 | `ec2-user` (Amazon Linux) or `ubuntu` (Ubuntu) |
| `EC2_PROJECT_PATH` | (Optional) Path where project should be cloned/built | `/home/asi/ASI-dashboard` (default) |

### EC2 Requirements

Your EC2 instance needs:

1. **Docker installed**
   ```bash
   # Install Docker on EC2
   sudo yum install docker -y  # Amazon Linux
   # OR
   sudo apt-get install docker.io -y  # Ubuntu
   sudo systemctl start docker
   sudo systemctl enable docker
   sudo usermod -aG docker $USER
   ```

2. **Docker Compose** (if using docker-compose.yml)
   ```bash
   sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
   sudo chmod +x /usr/local/bin/docker-compose
   ```

3. **Git installed**
   ```bash
   sudo yum install git -y  # Amazon Linux
   # OR
   sudo apt-get install git -y  # Ubuntu
   ```

4. **SSH access** configured (the SSH key you add to GitHub secrets)

## Pipeline Steps Breakdown

1. **Checkout Code**: GitHub Actions checks out your code
2. **Configure SSH**: Sets up SSH connection to EC2
3. **Deploy to EC2**: 
   - Clones/pulls latest code to EC2
   - Removes old Docker images
   - Builds backend image directly on EC2 (no cache)
   - Builds frontend image directly on EC2 (no cache)
   - Restarts containers (docker-compose or direct Docker)

## Troubleshooting

### Pipeline Not Running?

- Make sure you're pushing to `main` or `master` branch
- Check that you're not only changing `.md` files (these are ignored)
- Verify the workflow file is in `.github/workflows/` directory
- Check that all required secrets are configured

### SSH Connection Failed?

- Verify `EC2_SSH_KEY` secret contains the complete private key
- Check that `EC2_HOST` is correct (IP or hostname)
- Ensure `EC2_USER` matches your EC2 instance user
- Test SSH connection manually: `ssh EC2_USER@EC2_HOST`
- Check EC2 security group allows SSH (port 22) from GitHub Actions IPs

### Build Failures on EC2?

- Check the Actions tab for detailed error messages
- SSH into EC2 and check Docker: `docker --version`
- Verify Dockerfiles are correct
- Check disk space on EC2: `df -h`
- View Docker logs: `docker logs asi-backend` or `docker logs asi-frontend`

### Containers Not Restarting?

- Check if docker-compose.yml exists in project root
- Verify containers are running: `docker ps`
- Check container logs: `docker logs asi-backend`
- Manually restart: `docker-compose restart` or `docker restart asi-backend`

## Customization

To modify the pipeline behavior, edit `.github/workflows/ci-cd.yml`:

- **Change trigger branches**: Modify the `on.push.branches` section
- **Change project path**: Update `EC2_PROJECT_PATH` secret or modify the default path in the script
- **Enable Docker cache**: Remove `--no-cache` flag in the build commands (faster but may use old layers)
- **Customize container restart**: Modify the container restart logic in the deployment script
- **Add pre-build steps**: Add commands before Docker build (e.g., run tests, install dependencies)
