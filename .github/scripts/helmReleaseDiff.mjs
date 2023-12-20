#!/usr/bin/env zx
$.verbose = false


/**
 * * helmReleaseDiff.mjs
 * * Runs `helm template` with your Helm values and then runs a diff tool across Argo Helm Charts
 * @param --source-chart      The source Helm chart to compare against the target
 * @param --target-chart      The target Helm chart to compare against the source
 * @param --diff-tool         The tool to use for diffing (`diff` or `dyff`)
 * * Limitations:
 * * Does not work with multiple HelmRelease maninfests in the same YAML document
 */
const SourceChart = argv['source-chart']
const TargetChart = argv['target-chart']
const diffTool = argv['diff-tool']

const helm = await which('helm')

async function helmChart(chartLocation) {
    const chart = await fs.readFile(`${chartLocation}/Chart.yaml`, 'utf8')
    const doc = YAML.parseAllDocuments(chart).map((item) => item.toJS())
    return doc[0]
}

async function helmTemplate(chartLocation) {

    const manifestsFile = await $`mktemp`

    await $`${helm} dep update ${chartLocation}`

    const manifests = await $`${helm} template ${chartLocation}`

    // Remove docs that are CustomResourceDefinition and keys which contain generated fields
    let documents = YAML.parseAllDocuments(manifests.stdout.trim())
    //documents = documents.filter(doc => doc.get('kind') !== 'CustomResourceDefinition')
    documents.forEach(doc => {
        const del = (path) => doc.hasIn(path) ? doc.deleteIn(path) : false
        del(['metadata', 'labels'])
        del(['spec', 'template', 'metadata', 'annotations'])
        del(['spec', 'template', 'metadata', 'labels'])
    })

    await fs.writeFile(manifestsFile.stdout.trim(), documents.map(doc => doc.toString({directives: true})).join('\n'))
    return manifestsFile.stdout.trim()
}

// Generate current template from Helm values
const sourceChart = await helmChart(SourceChart)
if (sourceChart) {

    const sourceChartName = sourceChart.name
    const sourceChartVersion = sourceChart.version
    const sourceChartRepositoryUrl = sourceChart.dependencies[0].repository

    const currentManifests = await helmTemplate(SourceChart)

    // Generate target template from Helm values
    const targetChart = await helmChart(TargetChart)
    const targetChartName = targetChart.name
    const targetChartVersion = targetChart.version
    const targetChartRepositoryUrl = targetChart.dependencies[0].repository

    const incomingManifests = await helmTemplate(TargetChart)

    let diffOutput = ""
    if (diffTool === 'diff') {
        const diff_tool = await which('diff')
        const diff_out = await $`${diff_tool} -u ${currentManifests} ${incomingManifests} || :`
        diffOutput = diff_out.stdout.trim();

    } else if (diffTool === 'dyff') {
        const dyff_tool = await which('dyff')
        const diff_out = await $`${dyff_tool} --color=off --truecolor=off between --omit-header --ignore-order-changes --detect-kubernetes=true --output=human ${currentManifests} ${incomingManifests}`
        diffOutput = diff_out.stdout.trim();
    }

    let comments = ''

    comments += `Path: ${TargetChart}\n`

    if (sourceChartName !== targetChartName) {
        comments += `Chart: ${sourceChartName} -> ${targetChartName}\n`
    }

    if (sourceChartVersion !== targetChartVersion) {
        comments += `Version: ${sourceChartVersion} -> ${targetChartVersion}\n`
    }

    if (sourceChartRepositoryUrl !== targetChartRepositoryUrl) {
        comments += `Registry URL: ${sourceChartRepositoryUrl} -> ${targetChartRepositoryUrl}\n`
    }

    comments += `\n\n`

    if (diffOutput !== '') {
        comments += "```diff\n"
        comments += diffOutput
        comments += "\n```"
    } else {
        comments += "```diff\nNo changes in detected in resources\n```"
    }

    echo(comments)

}
