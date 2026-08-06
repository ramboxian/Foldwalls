import {defineCliConfig} from 'sanity/cli'

export default defineCliConfig({
  api: {
    projectId: '3huccpow',
    dataset: 'production',
  },
  deployment: {
    appId: 'ilzn4ketssytbdo3e5lutpdl',
    autoUpdates: false,
  },
})
