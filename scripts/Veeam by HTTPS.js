var Veeam = {
  params: {},
  token: '',

  setParams: function (params) {
    ['api_endpoint', 'user', 'password', 'created_after'].forEach(function (field) {
      if (typeof params !== 'object' || typeof params[field] === 'undefined' || params[field] === '') {
        throw 'Required param is not set: ' + field + '.';
      }
    });

    Veeam.params = params;
    if (typeof Veeam.params.api_endpoint === 'string' && !Veeam.params.api_endpoint.endsWith('/')) {
      Veeam.params.api_endpoint += '/';
    }
    if (Veeam.params.created_after >= 365 || Veeam.params.created_after <= 1) {
      throw 'Incorrect "created_after" parameter given: ' + Veeam.params.created_after + '\nMust be between 1 and 365 days.';
    }
  },

  login: function () {

    var resp, login = new HttpRequest();
    if (typeof Veeam.params.http_proxy !== 'undefined' && Veeam.params.http_proxy !== '') {
      login.setProxy(Veeam.params.http_proxy);
    }
    login.addHeader('Content-Type: application/x-www-form-urlencoded');
    login.addHeader('x-api-version: 1.1-rev2');
    resp = login.post(Veeam.params.api_endpoint + 'api/oauth2/token',
      'grant_type=password&username=' + encodeURIComponent(Veeam.params.user) + '&password=' + encodeURIComponent(Veeam.params.password));

    if (login.getStatus() !== 200 || resp === null) {
      throw 'Login failed with status code ' + login.getStatus() + ': ' + resp;
    }

    try {
      resp = JSON.parse(resp);
    }
    catch (error) {
      throw 'Failed to parse authentication token for the logon session.';
    }
    if (!resp.hasOwnProperty('access_token')) {
      throw 'Auth response does not contain access token.';
    }
    Veeam.token = resp['access_token'];

  },

  request: function (url) {

    var response, request = new HttpRequest();
    if (typeof Veeam.params.http_proxy !== 'undefined' && Veeam.params.http_proxy !== '') {
      request.setProxy(Veeam.params.http_proxy);
    }
    if (Veeam.token) {
      request.addHeader('Authorization: Bearer ' + Veeam.token);
      request.addHeader('x-api-version: 1.1-rev2');
      response = request.get(url);
    }
    if (request.getStatus() !== 200 || response === null) {
      throw 'Request failed with status code ' + request.getStatus() + ': ' + response;
    }
    try {
      return JSON.parse(response);
    }
    catch (error) {
      throw 'Failed to parse response received from API.';
    }
  },

  getMetricsData: function () {
    var data = {};
    var session_history_depth = Veeam.params.session_history_depth || 3;

    // Get job states
    var jobs_response = Veeam.request(Veeam.params.api_endpoint + 'api/v1/jobs/states');
    var jobs = jobs_response.data || [];
    data['jobs_states'] = [];

    jobs.forEach(function (job) {
      var enrichedJob = job;

      try {
        var sessions_response = Veeam.request(
          Veeam.params.api_endpoint +
          'api/v1/sessions?jobIdFilter=' +
          job.id +
          '&limit=' +
          session_history_depth +
          '&orderDesc=true'
        );

        var sessions = sessions_response.data || [];
        enrichedJob.sessions = {};

        sessions.forEach(function (session, index) {
          enrichedJob.sessions[session.id] = {
            state: session.state,
            name: session.name,
            creationTime: session.creationTime,
            endTime: session.endTime,
            duration: session.endTime - session.creationTime,
            progressPercent: session.progressPercent,
            result: session.result
          };

          // Only extract message from the most recent session (first in sorted list)
          if (index === 0 && session.result && session.result.message) {
            enrichedJob.lastMessage = session.result.message;
          }
        });
      } catch (e) {
        enrichedJob.sessions = { error: 'Failed to fetch session history' };
        enrichedJob.lastMessage = 'Session fetch error';
      }

      data['jobs_states'].push(enrichedJob);
    });

    data['repositories_states'] = Veeam.request(Veeam.params.api_endpoint + 'api/v1/backupInfrastructure/repositories/states');

    return data;
  }


};

try {
  Veeam.setParams(JSON.parse(value));
  Veeam.login();
  return JSON.stringify(Veeam.getMetricsData());
}
catch (error) {
  error += (String(error).endsWith('.')) ? '' : '.';
  Zabbix.log(3, '[ VEEAM ] ERROR: ' + error);
  return JSON.stringify({ 'error': error });
}