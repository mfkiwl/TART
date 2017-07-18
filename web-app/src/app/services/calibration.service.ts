import { Injectable } from '@angular/core';
import { Http, Response } from '@angular/http';
import { PlatformLocation } from '@angular/common';
import 'rxjs/add/operator/map';

@Injectable()
export class CalibrationService {

    apiUrl: string = '';

    constructor(
        private http: Http,
        private platformLocation: PlatformLocation
    ) {
        this.apiUrl = platformLocation.getBaseHrefFromDOM() + 'api/v1';
    }

    getGain() {
        return this.http.get(`${this.apiUrl}/calibration/gain`)
            .map((res: Response) => {
                return res.json();
            });
    }
}