const test = require('node:test');
const assert = require('node:assert/strict');
const { execFileSync } = require('node:child_process');
const path = require('node:path');

test('PowerShell helpers refuse SDR writes and reads in HDR without claiming an HDR preset readback',
  { skip: process.platform !== 'win32' }, () => {
    const stdout = execFileSync('powershell.exe', ['-NoLogo','-NoProfile','-NonInteractive',
      '-ExecutionPolicy','RemoteSigned','-File',path.join(__dirname,'fixtures/hdr-availability.ps1')],
      { encoding:'utf8',windowsHide:true,timeout:20000 });
    const result = JSON.parse(stdout.trim());
    assert.equal(result.brightness_status.ok,true);
    assert.equal(result.brightness_status.display.controlAvailable,false);
    assert.equal(result.brightness_status.display.brightnessPercent,null);
    for(const key of ['brightness_set','brightness_adjust','picture_set','picture_delta']) {
      assert.equal(result[key].ok,false,key);
      assert.match(result[key].error,/OSD/);
    }
    assert.equal(result.picture_status.value,null);
    assert.deepEqual(result.picture_status.modes,[]);
    assert.deepEqual(result.picture_list.hdrModes,[]);
    assert.equal(result.picture_default.defaultProfileApplied,false);
    assert.equal(result.picture_default.defaultProfileSource,'monitor-on-hdr-entry');
    assert.deepEqual(result.counters,{brightnessWrites:0,pictureWrites:0,pictureReads:0});
  });
