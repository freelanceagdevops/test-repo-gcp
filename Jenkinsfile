pipeline {
    agent any

    environment {
        GOOGLE_APPLICATION_CREDENTIALS = credentials('gcp-service-account')  // GCP service account credentials
        GOOGLE_CLOUD_PROJECT = credentials('gcp-project-id')                 // GCP project ID
        IMAGE_TAG = "1.0.${currentBuild.number}"                             // Docker image versioning
        GITHUB_TOKEN = credentials('github-token')                           // GitHub token for private repo
        SCANNER_HOME = tool 'sonar-scanner'                                  // SonarQube scanner home
    }

    stages {
        stage('Clean Workspace') {
            steps {
                cleanWs()
            }
        }

        stage('Git Checkout') {
            steps {
                git branch: 'main', url: 'https://github.com/freelanceagdevops/test-repo-gcp.git'
            }
        }

        stage('Authenticate with Google Cloud') {
            steps {
                sh """
                    gcloud auth activate-service-account --key-file=${GOOGLE_APPLICATION_CREDENTIALS}
                    gcloud config set project ${GOOGLE_CLOUD_PROJECT}
                    gcloud auth configure-docker us-central1-docker.pkg.dev
                """
            }
        }

        stage('Scan Filesystem using Trivy') {
            steps {
                sh "trivy fs ."
            }
        }

        stage('SonarQube Analysis') {
            steps {
                withSonarQubeEnv('sonar-server') {
                    sh """
                    $SCANNER_HOME/bin/sonar-scanner -Dsonar.projectName=app \
                    -Dsonar.projectKey=app
                    """
                }
            }
        }

        stage('Quality Gate') {
            steps {
                script {
                    waitForQualityGate abortPipeline: false, credentialsId: 'Sonar-token'
                }
            }
        }

        stage('OWASP Dependency-Check Scan') {
            steps {
                dependencyCheck additionalArguments: '--scan ./ --disableYarnAudit --disableNodeAudit', odcInstallation: 'DP-Check'
                dependencyCheckPublisher pattern: '**/dependency-check-report.xml'
            }
        }

        stage('Authenticate & Build Docker Image') {
            steps {
                script {
                    sh 'cat $GOOGLE_APPLICATION_CREDENTIALS | docker login -u _json_key --password-stdin https://us-central1-docker.pkg.dev'
                    sh """
                    docker build -t hello:latest .
                    """
                }
            }
        }

        stage('Tag & Push Docker Image to GCP Artifact Registry') {
            steps {
                script {
                    sh 'cat $GOOGLE_APPLICATION_CREDENTIALS | docker login -u _json_key --password-stdin https://us-central1-docker.pkg.dev'
                    sh """
                    docker tag hello:latest us-central1-docker.pkg.dev/${GOOGLE_CLOUD_PROJECT}/docker-repo/hello:${IMAGE_TAG}
                    docker push us-central1-docker.pkg.dev/${GOOGLE_CLOUD_PROJECT}/docker-repo/hello:${IMAGE_TAG}
                    docker tag hello:latest us-central1-docker.pkg.dev/${GOOGLE_CLOUD_PROJECT}/docker-repo/hello:latest
                    docker push us-central1-docker.pkg.dev/${GOOGLE_CLOUD_PROJECT}/docker-repo/hello:latest
                    docker rmi us-central1-docker.pkg.dev/${GOOGLE_CLOUD_PROJECT}/docker-repo/hello:${IMAGE_TAG} || true
                    docker rmi hello:latest || true
                    docker volume prune -f
                    """
                }
            }
        }

        stage('Scan Latest Docker Image using Trivy') {
            steps {
                sh "trivy image us-central1-docker.pkg.dev/${GOOGLE_CLOUD_PROJECT}/docker-repo/hello:${IMAGE_TAG}"
            }
        }

        stage('Clean Workspace for CD Repo') {
            steps {
                cleanWs()
            }
        }

        stage('Checkout K8s YAML Repo') {
            steps {
                git branch: 'main', credentialsId: 'github-token', url: 'https://github.com/freelanceagdevops/test-k8s-gcp.git'
            }
        }

        stage('Update helm values.yaml with New Docker Image') {
            environment {
                GIT_REPO_NAME = "test-k8s"
                GIT_USER_NAME = "freelanceagdevops"
            }
            steps {
                withCredentials([string(credentialsId: 'github-token', variable: 'GITHUB_TOKEN')]) {
                    sh """
                    set -e  # Exit on any command failure

                    # Configure Git user details
                    git config user.email "freelanceagdevops@gmail.com"
                    git config user.name "${GIT_USER_NAME}"

                    # Print file before updating
                    echo "=== BEFORE ==="
                    cat helm/values.yaml

                    # Check for existing image pattern
                    echo "Checking for existing image in values.yaml:"
                    grep "image:" helm/values.yaml || echo "Pattern not found. Proceeding with replacement."

                    # Update helm values.yaml file with the new Docker image tag
                    sed -i "s|image: us-central1-docker.pkg.dev/.*/docker-repo/hello:.*|image: us-central1-docker.pkg.dev/${GOOGLE_CLOUD_PROJECT}/docker-repo/hello:${IMAGE_TAG}|" helm/values.yaml

                    # Print file after updating to confirm changes
                    echo "=== AFTER ==="
                    cat helm/values.yaml

                    # Check if there are any changes to commit
                    if git diff --quiet; then
                        echo "No changes to commit. Skipping commit."
                    else
                        # Commit and push changes to the repository
                        git add helm/values.yaml
                        git commit -m "Updated helm values.yaml to version ${IMAGE_TAG}"
                        git push @github.com/${GIT_USER_NAME}/${GIT_REPO_NAME}.git">https://${GITHUB_TOKEN}@github.com/${GIT_USER_NAME}/${GIT_REPO_NAME}.git HEAD:main
                    fi
                    """
                }
            }
        }

        stage('Updated Image tag for CD') {
            steps {
                echo 'Successfully updated Docker Image tag for Continuous Deployment'
            }
        }
    }
}
