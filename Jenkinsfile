def buildImage() {
    sh 'gcloud auth activate-service-account --key-file=${GCE_SERVICE_ACCOUNT_KEY}'
    sh 'utils/jenkins/build_image.sh'
}

pipeline {
    agent { label "jnlp_dind_buildx" }

    environment {
        IMAGE_NAME = "sh-oec"
        GAR_REPO = "viralize-143916/infra"
        GAR_LOCATIONS = "us"
        GCE_SERVICE_ACCOUNT_KEY = credentials('CI_GCR_SERVICE_ACCOUNT')
        
    }

    stages {
        stage('Build image') {
            steps {
                script {
                    buildImage()
                }
            }
        }
    }
}
